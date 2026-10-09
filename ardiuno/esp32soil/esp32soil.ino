#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_bt.h>
#if __has_include("esp_pm.h")
#include "esp_pm.h"
#endif

// --- Pin Definitions for Seeed Studio XIAO ESP32-C5 ---
// On Seeed Studio XIAO ESP32-C5:
// - Battery monitoring uses the built-in circuit: BAT_VOLT_PIN_EN (GPIO 26) enables the
//   TPS22916 load switch & 1:2 divider, and BAT_VOLT_PIN (GPIO 6) reads the analog voltage.
// - Capacitive Soil Sensor: Power (VCC) is supplied via D2 (GPIO 25) and analog signal is read on A0 (GPIO 1).

#ifndef BAT_VOLT_PIN
#define BAT_VOLT_PIN    6   // Internal ADC pin for battery voltage divider on XIAO ESP32-C5
#endif

#ifndef BAT_VOLT_PIN_EN
#define BAT_VOLT_PIN_EN 26  // Internal enable pin for battery voltage acquisition (TPS22916)
#endif

#ifndef SOIL_POWER_PIN
  #ifdef D2
    #define SOIL_POWER_PIN D2
  #else
    #define SOIL_POWER_PIN 25 // Physical pin D2 on XIAO ESP32-C5
  #endif
#endif

#ifndef SOIL_ANALOG_PIN
  #ifdef A0
    #define SOIL_ANALOG_PIN A0
  #else
    #define SOIL_ANALOG_PIN 1  // Physical pin A0 (D0) on XIAO ESP32-C5
  #endif
#endif

// Backward-compatibility aliases
#define ANALOG_PIN      SOIL_ANALOG_PIN
const int soilPin       = SOIL_ANALOG_PIN;

// --- Soil Sensor Calibration Variables ---
float soilDryVolt = 1.78f; // Voltage in dry air (0% moisture)
float soilWetVolt = 0.95f; // Voltage in water (100% moisture)
float lastMeasuredSoilVolt = 1.78f;
float lastNormalizedSoilVolt = 1.78f;

// --- Power Management & Light-Sleep Settings ---
#define LIGHT_SLEEP_WAKEUP_US   250000 // 250ms periodic light-sleep wakeup interval for BLE maintenance

// --- BLE UUID Definitions ---
#define DEVICE_NAME             "XIAO-ESP32-Soil"
#define SENSOR_SERVICE_UUID     "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SENSOR_DATA_CHAR_UUID   "beb5483e-36e1-4688-b7f5-ea07361b26a8"

#define BATTERY_SERVICE_UUID    "0000180f-0000-1000-8000-00805f9b34fb"
#define BATTERY_LEVEL_CHAR_UUID "00002a19-0000-1000-8000-00805f9b34fb"

BLEServer* pServer = nullptr;
BLECharacteristic* pSensorDataChar = nullptr;
BLECharacteristic* pBatteryLevelChar = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;
bool measurementsEnabled = false; // Off by default in Arduino firmware until activated by client/app or PC connection

unsigned long lastSensorReadTime = 0;
const unsigned long SENSOR_INTERVAL_MS = 1000; // Read & notify every 1 second

// --- Forward Declarations & Command Handler ---
void handleCommand(String valStr, const char* source) {
    valStr.trim();
    if (valStr.length() == 0) return;
    String upper = valStr;
    upper.toUpperCase();

    // 1. On / Off Controls
    if (upper == "0" || upper == "OFF" || upper == "STOP" || upper == "PAUSE") {
        measurementsEnabled = false;
        digitalWrite(SOIL_POWER_PIN, LOW);
        digitalWrite(BAT_VOLT_PIN_EN, LOW);
        Serial.print("["); Serial.print(source); Serial.println("] Measurements switched OFF (paused)");
    } else if (upper == "1" || upper == "ON" || upper == "START" || upper == "RESUME") {
        measurementsEnabled = true;
        Serial.print("["); Serial.print(source); Serial.println("] Measurements switched ON (active)");
    }
    // 2. Sensor Calibration Commands
    else if (upper == "CAL_DRY" || upper == "CAL:DRY" || upper == "SET_DRY") {
        // Calibrate dry point using last measured normalized voltage
        soilDryVolt = lastNormalizedSoilVolt;
        Serial.print("["); Serial.print(source); Serial.print("] Calibrated DRY point (0% moisture) to: ");
        Serial.print(soilDryVolt, 3);
        Serial.println(" V");
    } else if (upper == "CAL_WET" || upper == "CAL:WET" || upper == "SET_WET") {
        // Calibrate wet point using last measured normalized voltage
        soilWetVolt = lastNormalizedSoilVolt;
        Serial.print("["); Serial.print(source); Serial.print("] Calibrated WET point (100% moisture) to: ");
        Serial.print(soilWetVolt, 3);
        Serial.println(" V");
    } else if (upper == "CAL_RESET" || upper == "RESET_CAL" || upper == "CAL:RESET") {
        soilDryVolt = 1.78f;
        soilWetVolt = 0.95f;
        Serial.print("["); Serial.print(source); Serial.println("] Calibration reset to defaults (Dry: 1.78V, Wet: 0.95V)");
    } else if (upper.startsWith("SET_DRY:") || upper.startsWith("DRY:")) {
        int colonIdx = valStr.indexOf(':');
        if (colonIdx >= 0) {
            float v = valStr.substring(colonIdx + 1).toFloat();
            if (v > 0.05f && v <= 5.0f) {
                soilDryVolt = v;
                Serial.print("["); Serial.print(source); Serial.print("] Set custom DRY voltage to: ");
                Serial.print(soilDryVolt, 3);
                Serial.println(" V");
            }
        }
    } else if (upper.startsWith("SET_WET:") || upper.startsWith("WET:")) {
        int colonIdx = valStr.indexOf(':');
        if (colonIdx >= 0) {
            float v = valStr.substring(colonIdx + 1).toFloat();
            if (v > 0.01f && v <= 5.0f) {
                soilWetVolt = v;
                Serial.print("["); Serial.print(source); Serial.print("] Set custom WET voltage to: ");
                Serial.print(soilWetVolt, 3);
                Serial.println(" V");
            }
        }
    } else if (upper.startsWith("CAL:")) {
        // Format: CAL:1.80,0.95
        int colonIdx = valStr.indexOf(':');
        int commaIdx = valStr.indexOf(',');
        if (colonIdx >= 0 && commaIdx > colonIdx) {
            float dry = valStr.substring(colonIdx + 1, commaIdx).toFloat();
            float wet = valStr.substring(commaIdx + 1).toFloat();
            if (dry > 0.1f && wet > 0.01f) {
                soilDryVolt = dry;
                soilWetVolt = wet;
                Serial.print("["); Serial.print(source); Serial.print("] Set 2-Point Calibration -> Dry: ");
                Serial.print(soilDryVolt, 3);
                Serial.print("V, Wet: ");
                Serial.print(soilWetVolt, 3);
                Serial.println("V");
            }
        }
    }
}

// --- BLE Characteristic Callbacks for Measurement & Calibration Control ---
class SensorCharCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) override {
        String value = pCharacteristic->getValue();
        if (value.length() > 0) {
            handleCommand(value, "BLE");
        }
    }
};

// --- BLE Server Callbacks ---
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) override {
        deviceConnected = true;
        Serial.println("[BLE] Client connected! Active telemetry enabled.");
    }

    void onDisconnect(BLEServer* pServer) override {
        deviceConnected = false;
        measurementsEnabled = false; // Turn off measurements when disconnected to save energy
        digitalWrite(SOIL_POWER_PIN, LOW);
        digitalWrite(BAT_VOLT_PIN_EN, LOW);
        Serial.println("[BLE] Client disconnected! Restarting BLE advertising...");

        // Restart advertising immediately so phones can discover and reconnect quickly
        delay(100);
        BLEDevice::startAdvertising();
    }
};

// --- Automatic Power Management Configuration ---
void configurePowerManagement() {
#if defined(CONFIG_PM_ENABLE)
    esp_pm_config_t pm_config = {
        .max_freq_mhz = 160,
        .min_freq_mhz = 40,
        .light_sleep_enable = true
    };
    esp_pm_configure(&pm_config);
    Serial.println("[PWR] ESP32 Dynamic Power Management enabled.");
#endif
}

void setupBLE() {
    Serial.println("[BLE] Initializing BLE Server...");
    BLEDevice::init(DEVICE_NAME);

    // Set BLE TX Power for maximum range and discoverability
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9);
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV, ESP_PWR_LVL_P9);

    // Create BLE Server
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // 1. Create Standard Battery Service
    BLEService* pBatService = pServer->createService(BATTERY_SERVICE_UUID);
    pBatteryLevelChar = pBatService->createCharacteristic(
        BATTERY_LEVEL_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pBatteryLevelChar->addDescriptor(new BLE2902());
    pBatService->start();

    // 2. Create Custom Soil & Sensor Telemetry Service with Read, Write (for On/Off control), & Notify
    BLEService* pSensorService = pServer->createService(SENSOR_SERVICE_UUID);
    pSensorDataChar = pSensorService->createCharacteristic(
        SENSOR_DATA_CHAR_UUID,
        BLECharacteristic::PROPERTY_READ |
        BLECharacteristic::PROPERTY_WRITE |
        BLECharacteristic::PROPERTY_NOTIFY
    );
    pSensorDataChar->addDescriptor(new BLE2902());
    pSensorDataChar->setCallbacks(new SensorCharCallbacks());
    pSensorDataChar->setValue("{\"status\":\"initializing\"}");
    pSensorService->start();

    // Configure Advertising:
    // Split payload across primary advertisement and scan response so each stays under the 31-byte limit.
    // Primary packet: Flags + Complete Local Name + 16-bit Battery Service UUID (fits in 24 bytes <= 31 bytes)
    BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();

    BLEAdvertisementData advData;
    advData.setFlags(0x06); // General Discoverable + BR/EDR Not Supported
    advData.setName(DEVICE_NAME); // "XIAO-ESP32-Soil"
    advData.setCompleteServices(BLEUUID(BATTERY_SERVICE_UUID));
    pAdvertising->setAdvertisementData(advData);

    // Scan Response packet: 128-bit Custom Soil Sensor Service UUID + Name
    BLEAdvertisementData scanResponseData;
    scanResponseData.setCompleteServices(BLEUUID(SENSOR_SERVICE_UUID));
    scanResponseData.setName(DEVICE_NAME);
    pAdvertising->setScanResponseData(scanResponseData);

    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // Helper for Apple/iOS connection parameters
    pAdvertising->setMinPreferred(0x12);
    // Fast, responsive advertising interval (40ms - 80ms) ensures instant phone discovery
    pAdvertising->setMinInterval(0x40); // 40ms (64 * 0.625ms)
    pAdvertising->setMaxInterval(0x80); // 80ms (128 * 0.625ms)
    BLEDevice::startAdvertising();

    Serial.println("[BLE] Advertising started (40-80ms interval). Waiting for connections...");
}

bool oldPcConnected = false;

void setup() {
    Serial.begin(115200);
    delay(1000);

    // Initialize Battery monitoring circuit
    pinMode(BAT_VOLT_PIN, INPUT);
    pinMode(BAT_VOLT_PIN_EN, OUTPUT);
    digitalWrite(BAT_VOLT_PIN_EN, LOW); // Keep battery acquisition circuit off when idle to save power

    // Initialize Soil Sensor pins
    pinMode(SOIL_POWER_PIN, OUTPUT);
    digitalWrite(SOIL_POWER_PIN, LOW); // Keep capacitive soil sensor unpowered by default
    pinMode(SOIL_ANALOG_PIN, INPUT);

    // Configure Power Management and BLE
    configurePowerManagement();
    setupBLE();

    Serial.println("[PWR] Power management initialized. Sensor circuits powered down when disconnected.");
}

void loop() {
    // -------------------------------------------------------------------------
    // 1. Process Incoming Serial Commands from PC
    // -------------------------------------------------------------------------
    if (Serial.available() > 0) {
        String serialCmd = Serial.readStringUntil('\n');
        handleCommand(serialCmd, "SERIAL");
    }

    // Check if connected to PC (USB Serial Monitor or CDC port active)
    bool pcConnected = (bool)Serial;

    // Handle PC connection state changes
    if (pcConnected && !oldPcConnected) {
        oldPcConnected = true;
        Serial.println("[SYS] PC Serial connection detected. Running active measurement mode.");
    } else if (!pcConnected && oldPcConnected) {
        oldPcConnected = false;
    }

    bool isActive = deviceConnected || pcConnected;

    // -------------------------------------------------------------------------
    // 2. Standby Mode when Disconnected (No BLE & No PC)
    // When neither a PC nor a Bluetooth client is connected, power down external
    // sensor circuits to conserve energy, while yielding CPU time to FreeRTOS so
    // BLE advertising packets are reliably broadcast.
    // -------------------------------------------------------------------------
    if (!isActive) {
        // Ensure sensor hardware and dividers are completely powered off
        digitalWrite(SOIL_POWER_PIN, LOW);
        digitalWrite(BAT_VOLT_PIN_EN, LOW);

        // Handle BLE Re-advertising failsafe after a disconnect
        if (oldDeviceConnected) {
            delay(100);
            pServer->startAdvertising();
            Serial.println("[BLE] Restarted advertising after disconnect.");
            oldDeviceConnected = false;
        }

        // Yield CPU to FreeRTOS to service BLE advertising and background tasks
        delay(50);
        return;
    }

    // Handle connection state transition from disconnected to connected
    if (deviceConnected && !oldDeviceConnected) {
        oldDeviceConnected = true;
        Serial.println("[BLE] Connection active. Running in normal operational mode.");
    }

    unsigned long currentMillis = millis();
    bool shouldMeasure = measurementsEnabled || pcConnected;

    if (shouldMeasure && (currentMillis - lastSensorReadTime >= SENSOR_INTERVAL_MS)) {
        lastSensorReadTime = currentMillis;

        // =========================================================================
        // 1. Read Onboard Battery Voltage via Dedicated Circuit
        // Enable BAT_VOLT_PIN_EN (GPIO 26) on XIAO ESP32-C5 to sample BAT_VOLT_PIN (GPIO 6)
        // =========================================================================
        digitalWrite(BAT_VOLT_PIN_EN, HIGH);
        delay(15); // Allow load switch (TPS22916) and divider to settle

        uint32_t Vbatt = 0;
        for (int i = 0; i < 16; i++) {
            Vbatt += analogReadMilliVolts(BAT_VOLT_PIN);
            delay(1);
        }
        digitalWrite(BAT_VOLT_PIN_EN, LOW); // Turn off battery divider to minimize parasitic draw

        // On XIAO ESP32-C5 battery divider circuit (2:1 divider factor from 2x 100k resistors)
        float Vbattf = (2.0f * Vbatt) / 16.0f / 1000.0f;
        float percent = (Vbattf - 3.0f) / (4.2f - 3.0f) * 100.0f;
        if (percent > 100.0f) percent = 100.0f;
        if (percent < 0.0f) percent = 0.0f;

        // Determine effective sensor supply voltage from D2 (tracks 3.3V rail or battery if lower)
        float vSupply = (Vbattf >= 2.5f && Vbattf < 3.3f) ? Vbattf : 3.3f;

        // =========================================================================
        // 2. Power and Read Capacitive Soil Moisture Sensor on D2 / A0
        // Power ON soil sensor via D2 (GPIO 25), wait for oscillator to stabilize,
        // read analog output on A0 (GPIO 1), and power OFF to save energy and probe life.
        // =========================================================================
        digitalWrite(SOIL_POWER_PIN, HIGH);
        delay(50); // Stabilization time for 555 oscillator & peak detector

        uint32_t soilMvSum = 0;
        int rawSoilSum = 0;
        for (int i = 0; i < 16; i++) {
            soilMvSum += analogReadMilliVolts(SOIL_ANALOG_PIN);
            rawSoilSum += analogRead(SOIL_ANALOG_PIN);
            delay(1);
        }

        // Power down soil sensor immediately after reading
        digitalWrite(SOIL_POWER_PIN, LOW);

        float measuredSoilVoltage = (soilMvSum / 16.0f) / 1000.0f;
        int sensorValue = rawSoilSum / 16;

        // =========================================================================
        // 3. Compensate Soil Reading for Supply Voltage & Calibration
        // Capacitive sensor output is ratiometric to supply voltage (D2 / battery).
        // Normalize measured voltage to 3.3V reference level:
        // Vsoil_normalized = Vsoil_measured * (3.3V / Vsupply)
        // =========================================================================
        float soilVoltage = measuredSoilVoltage * (3.3f / vSupply);
        lastMeasuredSoilVolt = measuredSoilVoltage;
        lastNormalizedSoilVolt = soilVoltage;

        // Calculate soil moisture percentage (Inverted: lower voltage = wetter)
        float denom = (soilDryVolt - soilWetVolt);
        if (denom == 0.0f) denom = 0.001f;
        float soilPercent = (soilDryVolt - soilVoltage) / denom * 100.0f;
        if (soilPercent > 100.0f) soilPercent = 100.0f;
        if (soilPercent < 0.0f) soilPercent = 0.0f;

        // =========================================================================
        // 4. Output Results to Serial Monitor
        // =========================================================================
        Serial.print("Battery: ");
        Serial.print(Vbattf, 3);
        Serial.print(" V (");
        Serial.print(percent, 1);
        Serial.print("%) | Soil: ");
        Serial.print(soilPercent, 1);
        Serial.print("% (Voltage: ");
        Serial.print(soilVoltage, 2);
        Serial.print("V, Raw: ");
        Serial.print(sensorValue);
        Serial.print(", Dry: ");
        Serial.print(soilDryVolt, 2);
        Serial.print("V, Wet: ");
        Serial.print(soilWetVolt, 2);
        Serial.print("V, Measured: ");
        Serial.print(measuredSoilVoltage, 2);
        Serial.print("V, Supply: ");
        Serial.print(vSupply, 2);
        Serial.println("V)");

        // =========================================================================
        // 5. Update BLE Characteristics & Send Notifications
        // =========================================================================
        if (deviceConnected) {
            // 5a. Update standard battery level (uint8 0-100)
            uint8_t batLevel = (uint8_t)percent;
            pBatteryLevelChar->setValue(&batLevel, 1);
            pBatteryLevelChar->notify();

            // 5b. Send JSON telemetry payload via sensor characteristic (including calibration points)
            char jsonBuffer[220];
            snprintf(
                jsonBuffer,
                sizeof(jsonBuffer),
                "{\"bat_v\":%.3f,\"bat_pct\":%.1f,\"soil_pct\":%.1f,\"soil_v\":%.2f,\"soil_raw\":%d,\"dry_v\":%.2f,\"wet_v\":%.2f}",
                Vbattf,
                percent,
                soilPercent,
                soilVoltage,
                sensorValue,
                soilDryVolt,
                soilWetVolt
            );

            pSensorDataChar->setValue(jsonBuffer);
            pSensorDataChar->notify();
        }
    }

    delay(20); // Small yield for RTOS task scheduling
}