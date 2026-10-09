# XIAO ESP32-C5 Bluetooth Controller

A Flutter application designed to discover, connect to, and interact with the **Seeed Studio XIAO ESP32C5** (and other ESP32 devices) over Bluetooth Low Energy (BLE).

---

## Features

- **Bluetooth Adapter State Management**: Real-time monitoring of Bluetooth status (prompting users to enable Bluetooth if turned off).
- **BLE Device Scanning**: Scans for nearby BLE devices with live RSSI signal strength indicators and connectability status.
- **Smart ESP32 Detection**: Highlights and badges devices matching `XIAO`, `ESP32`, `C5`, and `Seeed` for quick identification, with quick filter chips and search.
- **Battery & Soil Capacitive Moisture Visualisations**:
  - **Battery Visualiser**: Interactive Battery Cell widget, Radial Arc Gauge, and detailed Diagnostics (voltage curve, state of charge, cutoff/max limits).
  - **Soil Moisture Visualiser**: Visual soil container/pot graphic with live animated water/moisture wave level, circular Soil Moisture Gauge, and Capacitive Sensor Calibration Diagnostic panel (SEN0193 dry/wet voltage calibration).
  - **Live Multi-Sensor Trend Chart**: Real-time historical chart plotting both Battery (%) and Soil Moisture (%) over time.
  - **Interactive Simulation / Demo Mode**: Test and explore all visualisations with manual sliders and animated sensor data generation even without physical hardware.
  - **Auto-Subscribe Sensors**: One-tap subscription to BLE Battery (`0x180F` / `0x2A19`) and Custom Soil & Telemetry GATT services.
- **GATT Service & Characteristic Discovery**: Automatically discovers all GATT services and characteristics upon connection.
- **Read & Write Characteristics**: Send UTF-8 commands/strings or hex data to writable characteristics and read values on demand.
- **Real-Time Notifications**: Subscribe/unsubscribe to characteristic notifications with live updates.
- **Live Terminal Console Log**: Real-time communication and event logs with timestamps.

---

## ESP32 Soil & Battery BLE Sketch (`ardiuno/esp32soil/esp32soil.ino`)

The Arduino sketch in `ardiuno/esp32soil/esp32soil.ino` monitors battery voltage and capacitive soil moisture (SEN0193), transmitting telemetry over BLE:
- **Instant Discovery & Power Management**: Fast 40–80ms BLE advertising intervals with boosted +9dBm TX power and FreeRTOS task yielding, ensuring smartphones discover the device immediately on the first scan cycle.
- **Duty-Cycled Sensor Hardware**: Capacitive soil sensor on `D2` and battery ADC divider load switch on `BAT_VOLT_PIN_EN` remain completely unpowered when idle/disconnected, minimizing power consumption.
- **PC & Bluetooth Auto-Active Mode**: When connected to a PC via USB Serial or connected to a mobile app via BLE, active continuous sensor measurements and telemetry notifications are enabled.
- **Interactive Calibration & Commands**: Full support for remote/serial commands (`ON`, `OFF`, `CAL_DRY`, `CAL_WET`, `CAL_RESET`, `CAL:<dry>,<wet>`).
- **Standard BLE Battery Service** (`0x180F` -> `0x2A19` uint8 battery percentage)
- **Custom Sensor Service** (`4fafc201-1fb5-459e-8fcc-c5c9c331914b` -> `beb5483e-36e1-4688-b7f5-ea07361b26a8` JSON telemetry payload with dynamic 2-point calibration)
- Real-time Serial monitor telemetry output.

---

## Getting Started

### 1. Prerequisites
- Flutter SDK (v3.13+)
- Android device or emulator with Bluetooth support

### 2. Run the App
```bash
flutter pub get
flutter run
```

---

## Example ESP32 Arduino BLE Sketch (for XIAO ESP32-C5)

Upload this example sketch to your Seeed Studio XIAO ESP32-C5 using the Arduino IDE with the ESP32 board package:

```cpp
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <esp_bt.h>

#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Client connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Client disconnected! Restarting advertising...");
      delay(100);
      BLEDevice::startAdvertising();
    }
};

class MyCharacteristicCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue();
      if (value.length() > 0) {
        Serial.print("Received from app: ");
        for (int i = 0; i < value.length(); i++) {
          Serial.print(value[i]);
        }
        Serial.println();
      }
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting XIAO ESP32-C5 BLE Server...");

  // Initialize BLE Device
  BLEDevice::init("XIAO-ESP32C5");

  // Boost TX Power for maximum range and discovery
  esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9);
  esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_ADV, ESP_PWR_LVL_P9);

  // Create BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY |
                      BLECharacteristic::PROPERTY_INDICATE
                    );

  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setValue("Hello from XIAO ESP32-C5");

  // Start service & advertising
  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  pAdvertising->setMinInterval(0x40); // 40ms interval
  pAdvertising->setMaxInterval(0x80); // 80ms interval
  BLEDevice::startAdvertising();

  Serial.println("BLE Advertising started. Ready to connect!");
}

void loop() {
  if (!deviceConnected) {
    // Standby: external sensors off, yield CPU to FreeRTOS to maintain BLE advertising
    delay(50);
    return;
  }

  // Active connected mode: send periodic notifications or handle sensor telemetry
  delay(1000);
}
```
