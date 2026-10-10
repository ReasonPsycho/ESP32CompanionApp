#include <Arduino.h>
#include <Adafruit_NeoPixel.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// --- PIN DEFINITIONS ---
#define LED_PIN    7       // GPIO 7 on XIAO ESP32-C5 (WS2812 NeoPixel data)
#define NUM_LEDS   64      // 8x8 Matrix
#define DEFAULT_BRIGHTNESS 1 // Default brightness (1-255)
#define GRID_SIZE  8

// --- POWER / CURRENT LIMIT DEFINITIONS ---
#define MAX_POWER_MILLIAMPS     1500  // Strict 1500mA (1.5A) hardware safety limit
#define QUIESCENT_CURRENT_MA    64    // ~1mA baseline per WS2812B IC when LEDs are dark (64 * 1mA)
#define SUBPIXEL_MAX_MA         20.0f // ~20mA per subpixel (R, G, B) at full intensity (255)

uint16_t currentLimitMa = MAX_POWER_MILLIAMPS;
uint16_t estimatedCurrentMa = QUIESCENT_CURRENT_MA;
bool isPowerLimited = false;

// Battery monitoring pins for Seeed Studio XIAO ESP32-C5
#ifndef BAT_VOLT_PIN
#define BAT_VOLT_PIN    6   // Internal ADC pin for battery voltage divider
#endif

#ifndef BAT_VOLT_PIN_EN
#define BAT_VOLT_PIN_EN 26  // Internal enable pin for battery voltage acquisition
#endif

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

// --- BLE UUID DEFINITIONS ---
#define DEVICE_NAME             "XIAO-ESP32-LED"

// Dedicated LED Matrix Service & Characteristics
#define LED_SERVICE_UUID        "8411e2dc-0001-4ddf-9729-c5c7d6e50001"
#define LED_COMMAND_CHAR_UUID   "8411e2dc-0002-4ddf-9729-c5c7d6e50001"
#define LED_STATUS_CHAR_UUID    "8411e2dc-0003-4ddf-9729-c5c7d6e50001"
#define LED_MATRIX_CHAR_UUID    "8411e2dc-0004-4ddf-9729-c5c7d6e50001"

// Standard Battery Service UUIDs
#define BATTERY_SERVICE_UUID    "0000180f-0000-1000-8000-00805f9b34fb"
#define BATTERY_LEVEL_CHAR_UUID "00002a19-0000-1000-8000-00805f9b34fb"

// Alias compatibility service for generic BLE controllers
#define GENERIC_SERVICE_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define GENERIC_CHAR_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"

// --- GAME & SYSTEM MODES ---
// 0 = Conway's Game of Life
// 1 = Tetris (Auto AI)
// 2 = Rainbow Wave Animation
// 3 = Custom Drawing Canvas
enum GameMode {
  MODE_LIFE = 0,
  MODE_TETRIS = 1,
  MODE_RAINBOW = 2,
  MODE_CUSTOM = 3
};

int activeGame = MODE_TETRIS;
bool isRunning = true;
uint8_t currentBrightness = DEFAULT_BRIGHTNESS;

// --- GENERAL TIMING & SPEED CONTROL ---
unsigned long lastUpdate = 0;
int gameSpeedMs = 400; // Global tick speed ms

// Telemetry & Battery timing
unsigned long lastTelemetryTime = 0;
const unsigned long TELEMETRY_INTERVAL_MS = 100; // Fast 10Hz telemetry updates
unsigned long lastBatteryReadTime = 0;
const unsigned long BATTERY_INTERVAL_MS = 3000;
float batteryVoltage = 3.90f;
uint8_t batteryPercent = 85;

// --- GAME OF LIFE VARS ---
bool currentGrid[GRID_SIZE][GRID_SIZE];
bool nextGrid[GRID_SIZE][GRID_SIZE];
uint32_t lifeColor = 0x00FF88; // Neon Green/Cyan

// --- TETRIS VARS & DEFINITIONS ---
uint32_t tetrisBoard[GRID_SIZE][GRID_SIZE];
int tetrisScore = 0;
int tetrisLines = 0;

struct Piece {
  int shape[2][2];
  uint32_t color;
  int x, y;
};

Piece currentPiece;
int targetX = 3;
int targetRot = 0;

const int SHAPES[3][2][2] = {
  { {1, 1}, {1, 1} }, // O-Piece
  { {1, 1}, {0, 0} }, // Horizontal 2-block
  { {1, 0}, {1, 1} }  // L-corner
};

const uint32_t PIECE_COLORS[3] = {
  0xFFFF00, // Yellow
  0x00FFFF, // Cyan
  0xFF00FF  // Magenta
};

// --- RAINBOW EFFECT VARS ---
uint16_t rainbowHue = 0;

// --- CUSTOM DRAW CANVAS BUFFER ---
uint32_t customCanvas[GRID_SIZE][GRID_SIZE];

// --- BLE GLOBALS ---
BLEServer* pServer = nullptr;
BLECharacteristic* pCommandChar = nullptr;
BLECharacteristic* pStatusChar = nullptr;
BLECharacteristic* pMatrixChar = nullptr;
BLECharacteristic* pBatteryChar = nullptr;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// --- FORWARD DECLARATIONS ---
void seedGrid();
void spawnTetrisPiece();
void decideAITarget();
void lockTetrisPiece();
void runGameOfLife();
void runTetris();
void runRainbow();
void renderCustomCanvas();
void handleCommand(String cmd, const char* source);
void sendTelemetry();
void sendMatrixFrame();
void updateBatteryReading();
void showPowerManaged();
void rotateShape(int shape[2][2]);
bool checkCollisionAt(int shape[2][2], int px, int py);
bool checkTetrisCollision(int offsetX, int offsetY);

// --- HELPER FUNCTION (SERPENTINE MATRIX) ---
int xyToIndex(int x, int y) {
  if (x < 0 || x >= GRID_SIZE || y < 0 || y >= GRID_SIZE) return 0;
  if (y % 2 == 1) {
    return y * GRID_SIZE + (GRID_SIZE - 1 - x);
  } else {
    return y * GRID_SIZE + x;
  }
}

// Convert 24-bit RGB to 16-bit 565 or compact representation
uint32_t colorWheel(byte pos) {
  pos = 255 - pos;
  if (pos < 85) {
    return strip.Color(255 - pos * 3, 0, pos * 3);
  }
  if (pos < 170) {
    pos -= 85;
    return strip.Color(0, pos * 3, 255 - pos * 3);
  }
  pos -= 170;
  return strip.Color(pos * 3, 255 - pos * 3, 0);
}

// --- BLE CALLBACKS ---
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) override {
    deviceConnected = true;
    Serial.println("[BLE] Client Connected!");
    // Request fast connection interval (7.5ms - 20ms) for ultra-low latency updates
    pServer->updateConnParams(pServer->getConnId(), 0x06, 0x10, 0, 400);
  }

  void onDisconnect(BLEServer* pServer) override {
    deviceConnected = false;
    Serial.println("[BLE] Client Disconnected.");
  }
};

class CommandCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    String rxValue = pCharacteristic->getValue();
    if (rxValue.length() > 0) {
      handleCommand(rxValue, "BLE");
    }
  }
};

class MatrixCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) override {
    uint8_t* data = pCharacteristic->getData();
    size_t len = pCharacteristic->getLength();
    if (len == 64) {
      activeGame = MODE_CUSTOM;
      for (int y = 0; y < GRID_SIZE; y++) {
        for (int x = 0; x < GRID_SIZE; x++) {
          uint8_t byteVal = data[y * GRID_SIZE + x];
          // Unpack RRRGGGBB
          uint8_t r = ((byteVal >> 5) & 0x07) * 36;
          uint8_t g = ((byteVal >> 2) & 0x07) * 36;
          uint8_t b = (byteVal & 0x03) * 85;
          customCanvas[y][x] = strip.Color(r, g, b);
        }
      }
      renderCustomCanvas();
      sendTelemetry();
    }
  }
};

// --- BATTERY MEASUREMENT ---
void updateBatteryReading() {
  pinMode(BAT_VOLT_PIN_EN, OUTPUT);
  digitalWrite(BAT_VOLT_PIN_EN, HIGH);
  delayMicroseconds(50);

  int raw = analogRead(BAT_VOLT_PIN);
  digitalWrite(BAT_VOLT_PIN_EN, LOW);

  // Divider ratio 1:2 on XIAO ESP32-C5 (2x voltage at battery), ADC 3.3V reference
  float measuredV = (raw / 4095.0f) * 3.3f * 2.0f;
  if (measuredV > 2.5f && measuredV <= 4.4f) {
    batteryVoltage = measuredV;
    // Map 3.3V (0%) - 4.2V (100%)
    float pct = (batteryVoltage - 3.3f) / (4.2f - 3.3f) * 100.0f;
    batteryPercent = (uint8_t)constrain((int)pct, 0, 100);
  }

  if (pBatteryChar != nullptr && deviceConnected) {
    uint8_t level = batteryPercent;
    pBatteryChar->setValue(&level, 1);
    pBatteryChar->notify();
  }
}

// --- DYNAMIC POWER & CURRENT LIMITER (<= 1000mA / 1.0A) ---
void showPowerManaged() {
  uint8_t* pixels = strip.getPixels();
  if (pixels == nullptr) {
    strip.show();
    return;
  }

  // Calculate sum of all RGB channel intensities across 64 pixels
  // Adafruit_NeoPixel internally stores pixels in GRB format (3 bytes per pixel)
  uint32_t channelSum = 0;
  int totalBytes = NUM_LEDS * 3;
  for (int i = 0; i < totalBytes; i++) {
    channelSum += pixels[i];
  }

  // Calculate active LED current draw in mA: (channelSum / 255.0) * SUBPIXEL_MAX_MA
  float activeCurrentMa = (float)channelSum * (SUBPIXEL_MAX_MA / 255.0f);
  float totalCurrentMa = (float)QUIESCENT_CURRENT_MA + activeCurrentMa;

  if (totalCurrentMa > (float)currentLimitMa) {
    // Current exceeds the 1A threshold: compute precise dynamic attenuation factor
    float allowableActiveMa = max(0.0f, (float)currentLimitMa - (float)QUIESCENT_CURRENT_MA);
    float scale = (activeCurrentMa > 0.0f) ? (allowableActiveMa / activeCurrentMa) : 1.0f;

    for (int i = 0; i < totalBytes; i++) {
      pixels[i] = (uint8_t)((float)pixels[i] * scale);
    }

    estimatedCurrentMa = currentLimitMa;
    isPowerLimited = true;
  } else {
    estimatedCurrentMa = (uint16_t)round(totalCurrentMa);
    isPowerLimited = false;
  }

  strip.show();
}

// --- TELEMETRY BROADCAST ---
void sendTelemetry() {
  if (!deviceConnected) return;

  // JSON format status with power & current telemetry
  char statusBuf[192];
  snprintf(statusBuf, sizeof(statusBuf),
    "{\"game\":%d,\"auto\":true,\"speed\":%d,\"bright\":%d,\"score\":%d,\"lines\":%d,\"run\":%s,\"bat\":%d,\"cur\":%d,\"max_cur\":%d,\"pwr_lim\":%s}",
    activeGame,
    gameSpeedMs,
    currentBrightness,
    tetrisScore,
    tetrisLines,
    isRunning ? "true" : "false",
    batteryPercent,
    estimatedCurrentMa,
    currentLimitMa,
    isPowerLimited ? "true" : "false"
  );

  if (pStatusChar != nullptr) {
    pStatusChar->setValue(statusBuf);
    pStatusChar->notify();
  }
}

// Send packed matrix frame (64 bytes) only on explicit demand / drawing command
void sendMatrixFrame() {
  if (!deviceConnected || pMatrixChar == nullptr) return;

  uint8_t matrixFrame[64];
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int idx = xyToIndex(x, y);
      uint32_t c = strip.getPixelColor(idx);
      uint8_t r = (c >> 16) & 0xFF;
      uint8_t g = (c >> 8) & 0xFF;
      uint8_t b = c & 0xFF;
      // Pack into 1 byte: RRRGGGBB
      matrixFrame[y * GRID_SIZE + x] = ((r >> 5) << 5) | ((g >> 5) << 2) | (b >> 6);
    }
  }
  pMatrixChar->setValue(matrixFrame, 64);
  pMatrixChar->notify();
}

// --- COMMAND PARSER ---
void handleCommand(String cmd, const char* source) {
  cmd.trim();
  if (cmd.length() == 0) return;
  Serial.print("["); Serial.print(source); Serial.print(" CMD] ");
  Serial.println(cmd);

  String upper = cmd;
  upper.toUpperCase();

  // 1. GAME MODE SWITCHING
  if (upper.startsWith("GAME:") || upper.startsWith("MODE:")) {
    int colon = cmd.indexOf(':');
    String arg = cmd.substring(colon + 1);
    arg.trim();
    arg.toUpperCase();

    if (arg == "0" || arg == "LIFE" || arg == "GAMEOFLIFE") {
      activeGame = MODE_LIFE;
      seedGrid();
      Serial.println("Switched to Game of Life");
    } else if (arg == "1" || arg == "TETRIS" || arg == "TETRIS_AUTO" || arg == "AUTO") {
      activeGame = MODE_TETRIS;
      decideAITarget();
      Serial.println("Switched to Tetris Auto AI");
    } else if (arg == "2" || arg == "RAINBOW" || arg == "COLOR") {
      activeGame = MODE_RAINBOW;
      Serial.println("Switched to Rainbow Wave");
    } else if (arg == "3" || arg == "CUSTOM" || arg == "DRAW") {
      activeGame = MODE_CUSTOM;
      Serial.println("Switched to Custom Drawing Canvas");
    }
  }
  else if (upper == "S") {
    // Cycle modes
    activeGame = (activeGame + 1) % 4;
    if (activeGame == MODE_LIFE) seedGrid();
    if (activeGame == MODE_TETRIS) decideAITarget();
    Serial.print("Cycled to mode: "); Serial.println(activeGame);
  }

  // 2. TETRIS CONTROLS
  else if (upper == "RESET" || upper == "RESTART") {
    memset(tetrisBoard, 0, sizeof(tetrisBoard));
    tetrisScore = 0;
    tetrisLines = 0;
    spawnTetrisPiece();
    Serial.println("Tetris board reset.");
  }

  // 3. GAME OF LIFE CONTROLS
  else if (upper == "SEED" || upper == "RANDOM") {
    seedGrid();
    Serial.println("Game of life re-seeded.");
  }
  else if (upper == "CLEAR") {
    if (activeGame == MODE_LIFE) {
      memset(currentGrid, 0, sizeof(currentGrid));
    } else if (activeGame == MODE_CUSTOM) {
      memset(customCanvas, 0, sizeof(customCanvas));
    } else if (activeGame == MODE_TETRIS) {
      memset(tetrisBoard, 0, sizeof(tetrisBoard));
    }
    strip.clear();
    showPowerManaged();
  }
  else if (upper == "STEP") {
    if (activeGame == MODE_LIFE) {
      runGameOfLife();
    }
  }
  else if (upper == "GLIDER") {
    activeGame = MODE_LIFE;
    memset(currentGrid, 0, sizeof(currentGrid));
    // Spawn standard glider
    currentGrid[1][2] = true;
    currentGrid[2][3] = true;
    currentGrid[3][1] = true;
    currentGrid[3][2] = true;
    currentGrid[3][3] = true;
  }
  else if (upper == "BLINKER") {
    activeGame = MODE_LIFE;
    memset(currentGrid, 0, sizeof(currentGrid));
    currentGrid[3][2] = true;
    currentGrid[3][3] = true;
    currentGrid[3][4] = true;
  }

  // 4. SPEED, BRIGHTNESS & POWER LIMIT CONTROLS
  else if (upper == "+" || upper == "=") {
    gameSpeedMs = max(20, gameSpeedMs - 25);
    Serial.print("Speed increased. Tick: "); Serial.print(gameSpeedMs); Serial.println(" ms");
  }
  else if (upper == "-") {
    gameSpeedMs = min(2000, gameSpeedMs + 25);
    Serial.print("Speed decreased. Tick: "); Serial.print(gameSpeedMs); Serial.println(" ms");
  }
  else if (upper.startsWith("SPEED:")) {
    int val = cmd.substring(6).toInt();
    if (val >= 20 && val <= 3000) {
      gameSpeedMs = val;
      Serial.print("Speed set to: "); Serial.print(gameSpeedMs); Serial.println(" ms");
    }
  }
  else if (upper.startsWith("BRIGHT:") || upper.startsWith("BRIGHTNESS:")) {
    int colon = cmd.indexOf(':');
    int val = cmd.substring(colon + 1).toInt();
    if (val >= 1 && val <= 255) {
      currentBrightness = (uint8_t)val;
      strip.setBrightness(currentBrightness);
      showPowerManaged();
      Serial.print("Brightness set to: "); Serial.println(currentBrightness);
    }
  }
  else if (upper.startsWith("LIMIT:") || upper.startsWith("CURRENT_LIMIT:") || upper.startsWith("MAX_CURRENT:")) {
    int colon = cmd.indexOf(':');
    int val = cmd.substring(colon + 1).toInt();
    if (val >= 50 && val <= MAX_POWER_MILLIAMPS) {
      currentLimitMa = (uint16_t)val;
      Serial.print("Current limit set to: "); Serial.print(currentLimitMa); Serial.println(" mA");
    } else if (val > MAX_POWER_MILLIAMPS) {
      currentLimitMa = MAX_POWER_MILLIAMPS;
      Serial.print("Current limit capped at safety ceiling: "); Serial.print(currentLimitMa); Serial.println(" mA (1.0A)");
    }
    showPowerManaged();
  }
  else if (upper == "ON" || upper == "START" || upper == "RESUME") {
    isRunning = true;
    Serial.println("Game / Display resumed");
  }
  else if (upper == "OFF" || upper == "STOP" || upper == "PAUSE") {
    isRunning = false;
    strip.clear();
    showPowerManaged();
    Serial.println("Game / Display paused & cleared");
  }

  // 5. CUSTOM DRAWING PIXEL & FRAME COMMANDS (Board updated during commands)
  else if (upper.startsWith("PIXEL:")) {
    activeGame = MODE_CUSTOM;
    // Format: PIXEL:x,y,r,g,b
    int p1 = cmd.indexOf(':');
    String rest = cmd.substring(p1 + 1);
    int c1 = rest.indexOf(',');
    int c2 = rest.indexOf(',', c1 + 1);
    int c3 = rest.indexOf(',', c2 + 1);
    int c4 = rest.indexOf(',', c3 + 1);

    if (c1 > 0 && c2 > 0 && c3 > 0 && c4 > 0) {
      int x = rest.substring(0, c1).toInt();
      int y = rest.substring(c1 + 1, c2).toInt();
      int r = rest.substring(c2 + 1, c3).toInt();
      int g = rest.substring(c3 + 1, c4).toInt();
      int b = rest.substring(c4 + 1).toInt();

      if (x >= 0 && x < GRID_SIZE && y >= 0 && y < GRID_SIZE) {
        customCanvas[y][x] = strip.Color(r, g, b);
        strip.setPixelColor(xyToIndex(x, y), customCanvas[y][x]);
        showPowerManaged();
      }
    }
  }
  else if (upper.startsWith("FILL:")) {
    activeGame = MODE_CUSTOM;
    int p1 = cmd.indexOf(':');
    String rest = cmd.substring(p1 + 1);
    int c1 = rest.indexOf(',');
    int c2 = rest.indexOf(',', c1 + 1);
    if (c1 > 0 && c2 > 0) {
      int r = rest.substring(0, c1).toInt();
      int g = rest.substring(c1 + 1, c2).toInt();
      int b = rest.substring(c2 + 1).toInt();
      uint32_t fillCol = strip.Color(r, g, b);
      for (int y = 0; y < GRID_SIZE; y++) {
        for (int x = 0; x < GRID_SIZE; x++) {
          customCanvas[y][x] = fillCol;
        }
      }
      renderCustomCanvas();
    }
  }
  else if (upper.startsWith("FRAME:") || upper.startsWith("BOARD:")) {
    activeGame = MODE_CUSTOM;
    int colon = cmd.indexOf(':');
    String hexStr = cmd.substring(colon + 1);
    hexStr.trim();
    if (hexStr.length() >= 128) {
      for (int i = 0; i < 64; i++) {
        char byteHex[3] = { hexStr[i * 2], hexStr[i * 2 + 1], '\0' };
        uint8_t byteVal = (uint8_t)strtol(byteHex, NULL, 16);
        int y = i / GRID_SIZE;
        int x = i % GRID_SIZE;
        uint8_t r = ((byteVal >> 5) & 0x07) * 36;
        uint8_t g = ((byteVal >> 2) & 0x07) * 36;
        uint8_t b = (byteVal & 0x03) * 85;
        customCanvas[y][x] = strip.Color(r, g, b);
      }
      renderCustomCanvas();
    }
  }
  else if (upper == "GET_BOARD" || upper == "GET_FRAME" || upper == "FRAME") {
    sendMatrixFrame();
  }

  // Send immediate state telemetry response
  sendTelemetry();
}

// --- HELPER TETRIS FUNCTIONS ---
void rotateShape(int shape[2][2]) {
  int temp[2][2];
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 2; c++) {
      temp[c][1 - r] = shape[r][c];
    }
  }
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 2; c++) {
      shape[r][c] = temp[r][c];
    }
  }
}

bool checkCollisionAt(int shape[2][2], int px, int py) {
  for (int r = 0; r < 2; r++) {
    for (int c = 0; c < 2; c++) {
      if (shape[r][c]) {
        int nx = px + c;
        int ny = py + r;

        if (nx < 0 || nx >= GRID_SIZE || ny >= GRID_SIZE) return true;
        if (ny >= 0 && tetrisBoard[ny][nx] != 0) return true;
      }
    }
  }
  return false;
}

bool checkTetrisCollision(int offsetX, int offsetY) {
  return checkCollisionAt(currentPiece.shape, currentPiece.x + offsetX, currentPiece.y + offsetY);
}

// --- GAME OF LIFE IMPLEMENTATION ---
void seedGrid() {
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      currentGrid[y][x] = random(100) < 35;
    }
  }
}

int countNeighbors(int x, int y) {
  int count = 0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue;
      int nx = (x + dx + GRID_SIZE) % GRID_SIZE;
      int ny = (y + dy + GRID_SIZE) % GRID_SIZE;
      if (currentGrid[ny][nx]) count++;
    }
  }
  return count;
}

void runGameOfLife() {
  bool changed = false;
  int totalLive = 0;

  // Render current frame
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int idx = xyToIndex(x, y);
      if (currentGrid[y][x]) {
        strip.setPixelColor(idx, lifeColor);
        totalLive++;
      } else {
        strip.setPixelColor(idx, strip.Color(0, 0, 0));
      }
    }
  }
  showPowerManaged();

  // Compute next state
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int neighbors = countNeighbors(x, y);
      bool alive = currentGrid[y][x];

      if (alive && (neighbors == 2 || neighbors == 3)) nextGrid[y][x] = true;
      else if (!alive && neighbors == 3) nextGrid[y][x] = true;
      else nextGrid[y][x] = false;

      if (nextGrid[y][x] != currentGrid[y][x]) changed = true;
    }
  }

  // Swap grids
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      currentGrid[y][x] = nextGrid[y][x];
    }
  }

  if (!changed || totalLive == 0) {
    seedGrid();
  }
}

// --- TETRIS AI IMPLEMENTATION ---
int evaluateBoardPlacement(int shape[2][2], int testX, int testY) {
  uint32_t tempBoard[GRID_SIZE][GRID_SIZE];
  memcpy(tempBoard, tetrisBoard, sizeof(tetrisBoard));

  for (int py = 0; py < 2; py++) {
    for (int px = 0; px < 2; px++) {
      if (shape[py][px]) {
        int ny = testY + py;
        int nx = testX + px;
        if (ny >= 0 && ny < GRID_SIZE && nx >= 0 && nx < GRID_SIZE) {
          tempBoard[ny][nx] = 1;
        }
      }
    }
  }

  int score = 0;

  for (int x = 0; x < GRID_SIZE; x++) {
    for (int y = 0; y < GRID_SIZE; y++) {
      if (tempBoard[y][x] != 0) {
        score += (GRID_SIZE - y) * 3;
        break;
      }
    }
  }

  for (int x = 0; x < GRID_SIZE; x++) {
    bool blockFound = false;
    for (int y = 0; y < GRID_SIZE; y++) {
      if (tempBoard[y][x] != 0) blockFound = true;
      else if (blockFound && tempBoard[y][x] == 0) score += 15;
    }
  }

  int clearedLines = 0;
  for (int y = 0; y < GRID_SIZE; y++) {
    bool full = true;
    for (int x = 0; x < GRID_SIZE; x++) {
      if (tempBoard[y][x] == 0) { full = false; break; }
    }
    if (full) clearedLines++;
  }
  score -= clearedLines * 25;

  return score;
}

void decideAITarget() {
  int bestScore = 10000;
  targetX = currentPiece.x;
  targetRot = 0;

  int testShape[2][2];

  for (int rot = 0; rot < 2; rot++) {
    memcpy(testShape, currentPiece.shape, sizeof(testShape));
    if (rot == 1) rotateShape(testShape);

    for (int testX = -1; testX < GRID_SIZE; testX++) {
      if (checkCollisionAt(testShape, testX, 0)) continue;

      int dropY = 0;
      while (!checkCollisionAt(testShape, testX, dropY + 1)) {
        dropY++;
      }

      int score = evaluateBoardPlacement(testShape, testX, dropY);
      if (score < bestScore) {
        bestScore = score;
        targetX = testX;
        targetRot = rot;
      }
    }
  }
}

void spawnTetrisPiece() {
  int type = random(0, 3);
  currentPiece.color = PIECE_COLORS[type];
  currentPiece.x = 3;
  currentPiece.y = 0;

  for (int py = 0; py < 2; py++) {
    for (int px = 0; px < 2; px++) {
      currentPiece.shape[py][px] = SHAPES[type][py][px];
    }
  }

  if (activeGame == MODE_TETRIS) {
    decideAITarget();
  }
}

void lockTetrisPiece() {
  for (int py = 0; py < 2; py++) {
    for (int px = 0; px < 2; px++) {
      if (currentPiece.shape[py][px]) {
        int boardY = currentPiece.y + py;
        int boardX = currentPiece.x + px;
        if (boardY >= 0 && boardY < GRID_SIZE) {
          tetrisBoard[boardY][boardX] = currentPiece.color;
        }
      }
    }
  }

  int clearedThisRound = 0;
  for (int y = GRID_SIZE - 1; y >= 0; y--) {
    bool fullRow = true;
    for (int x = 0; x < GRID_SIZE; x++) {
      if (tetrisBoard[y][x] == 0) {
        fullRow = false;
        break;
      }
    }
    if (fullRow) {
      clearedThisRound++;
      for (int moveY = y; moveY > 0; moveY--) {
        for (int x = 0; x < GRID_SIZE; x++) {
          tetrisBoard[moveY][x] = tetrisBoard[moveY - 1][x];
        }
      }
      for (int x = 0; x < GRID_SIZE; x++) tetrisBoard[0][x] = 0;
      y++;
    }
  }

  if (clearedThisRound > 0) {
    tetrisLines += clearedThisRound;
    tetrisScore += clearedThisRound * 100;
  }

  spawnTetrisPiece();

  if (checkTetrisCollision(0, 0)) {
    memset(tetrisBoard, 0, sizeof(tetrisBoard));
    tetrisScore = 0;
  }
}

void runTetris() {
  if (targetRot > 0) {
    int rotTemp[2][2];
    memcpy(rotTemp, currentPiece.shape, sizeof(rotTemp));
    rotateShape(rotTemp);
    if (!checkCollisionAt(rotTemp, currentPiece.x, currentPiece.y)) {
      memcpy(currentPiece.shape, rotTemp, sizeof(currentPiece.shape));
    }
    targetRot = 0;
  }

  if (currentPiece.x < targetX && !checkTetrisCollision(1, 0)) {
    currentPiece.x++;
  } else if (currentPiece.x > targetX && !checkTetrisCollision(-1, 0)) {
    currentPiece.x--;
  }

  if (!checkTetrisCollision(0, 1)) {
    currentPiece.y++;
  } else {
    lockTetrisPiece();
  }

  strip.clear();
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      if (tetrisBoard[y][x] != 0) {
        strip.setPixelColor(xyToIndex(x, y), tetrisBoard[y][x]);
      }
    }
  }

  for (int py = 0; py < 2; py++) {
    for (int px = 0; px < 2; px++) {
      if (currentPiece.shape[py][px]) {
        int renderX = currentPiece.x + px;
        int renderY = currentPiece.y + py;
        if (renderY >= 0 && renderY < GRID_SIZE) {
          strip.setPixelColor(xyToIndex(renderX, renderY), currentPiece.color);
        }
      }
    }
  }
  showPowerManaged();
}

// --- RAINBOW WAVE EFFECT ---
void runRainbow() {
  rainbowHue += 4;
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int idx = xyToIndex(x, y);
      byte colorIndex = (rainbowHue + (x * 16) + (y * 16)) & 255;
      strip.setPixelColor(idx, colorWheel(colorIndex));
    }
  }
  showPowerManaged();
}

// --- CUSTOM CANVAS RENDERING ---
void renderCustomCanvas() {
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      strip.setPixelColor(xyToIndex(x, y), customCanvas[y][x]);
    }
  }
  showPowerManaged();
}

// --- SETUP & BLE INITIALIZATION ---
void setup() {
  Serial.begin(115200);
  delay(100);
  Serial.println("\n====================================");
  Serial.println("  XIAO ESP32-C5 8x8 LED Controller  ");
  Serial.println("====================================");

  strip.begin();
  strip.setBrightness(currentBrightness);
  strip.clear();
  showPowerManaged();

  randomSeed(analogRead(0));
  seedGrid();
  spawnTetrisPiece();

  // Initialize BLE Device
  BLEDevice::init(DEVICE_NAME);
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  // 1. Create Dedicated LED Service
  BLEService* pLedService = pServer->createService(LED_SERVICE_UUID);

  // Command Characteristic (Write)
  pCommandChar = pLedService->createCharacteristic(
    LED_COMMAND_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR
  );
  pCommandChar->setCallbacks(new CommandCallbacks());
  pCommandChar->addDescriptor(new BLE2902());

  // Status Characteristic (Notify / Read)
  pStatusChar = pLedService->createCharacteristic(
    LED_STATUS_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusChar->addDescriptor(new BLE2902());

  // Matrix Characteristic (Notify / Read / Write / Write_NR)
  pMatrixChar = pLedService->createCharacteristic(
    LED_MATRIX_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pMatrixChar->setCallbacks(new MatrixCallbacks());
  pMatrixChar->addDescriptor(new BLE2902());

  pLedService->start();

  // 2. Create Standard Battery Service
  BLEService* pBatService = pServer->createService(BATTERY_SERVICE_UUID);
  pBatteryChar = pBatService->createCharacteristic(
    BATTERY_LEVEL_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pBatteryChar->addDescriptor(new BLE2902());
  pBatService->start();

  // 3. Create Generic Alias Service
  BLEService* pGenService = pServer->createService(GENERIC_SERVICE_UUID);
  BLECharacteristic* pGenChar = pGenService->createCharacteristic(
    GENERIC_CHAR_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_WRITE |
    BLECharacteristic::PROPERTY_WRITE_NR |
    BLECharacteristic::PROPERTY_NOTIFY
  );
  pGenChar->setCallbacks(new CommandCallbacks());
  pGenChar->addDescriptor(new BLE2902());
  pGenService->start();

  // 4. Start Advertising
  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(LED_SERVICE_UUID);
  pAdvertising->addServiceUUID(BATTERY_SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06); // 7.5ms min interval for fast responsiveness
  pAdvertising->setMaxPreferred(0x10); // 20ms max interval
  BLEDevice::startAdvertising();

  Serial.println("[BLE] Advertising started as: " DEVICE_NAME);
  updateBatteryReading();
}

void loop() {
  // Handle Disconnection / Re-advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // Give Bluetooth stack time to get ready
    pServer->startAdvertising();
    Serial.println("[BLE] Restarted advertising...");
    oldDeviceConnected = deviceConnected;
  }
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Serial command parser (identical to BLE commands)
  if (Serial.available()) {
    String sCmd = Serial.readStringUntil('\n');
    sCmd.trim();
    if (sCmd.length() > 0) {
      handleCommand(sCmd, "SERIAL");
    }
  }

  // Periodic Battery & Telemetry updates
  unsigned long now = millis();
  if (now - lastBatteryReadTime >= BATTERY_INTERVAL_MS) {
    lastBatteryReadTime = now;
    updateBatteryReading();
  }

  if (now - lastTelemetryTime >= TELEMETRY_INTERVAL_MS) {
    lastTelemetryTime = now;
    sendTelemetry();
  }

  // Unified global tick clock for display / games
  if (isRunning && (now - lastUpdate >= (unsigned long)gameSpeedMs)) {
    lastUpdate = now;

    switch (activeGame) {
      case MODE_LIFE:
        runGameOfLife();
        break;
      case MODE_TETRIS:
        runTetris();
        break;
      case MODE_RAINBOW:
        runRainbow();
        break;
      case MODE_CUSTOM:
        renderCustomCanvas();
        break;
      default:
        strip.clear();
        showPowerManaged();
        break;
    }
  }
}