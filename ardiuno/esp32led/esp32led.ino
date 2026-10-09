#include <Adafruit_NeoPixel.h>

#define LED_PIN    7       // GPIO 7 on XIAO ESP32-C5
#define NUM_LEDS   64      // 8x8 Matrix
#define BRIGHTNESS 5      // Max brightness capped at 15/255

#define GRID_SIZE  8

Adafruit_NeoPixel strip(NUM_LEDS, LED_PIN, NEO_GRB + NEO_KHZ800);

bool currentGrid[GRID_SIZE][GRID_SIZE];
bool nextGrid[GRID_SIZE][GRID_SIZE];

// Converts 2D (x, y) coordinates to a 1D pixel index
// (Adjusts for standard row-major order: Row 0 -> LEDs 0-7, Row 1 -> LEDs 8-15, etc.)
int xyToIndex(int x, int y) {
  return y * GRID_SIZE + x;
}

// Seed the grid randomly with ~35% live cells
void seedGrid() {
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      currentGrid[y][x] = random(100) < 35;
    }
  }
}

// Count active neighbors around cell (x, y) with boundary wrap-around (toroidal)
int countNeighbors(int x, int y) {
  int count = 0;
  for (int dy = -1; dy <= 1; dy++) {
    for (int dx = -1; dx <= 1; dx++) {
      if (dx == 0 && dy == 0) continue; // Skip the cell itself
      int nx = (x + dx + GRID_SIZE) % GRID_SIZE;
      int ny = (y + dy + GRID_SIZE) % GRID_SIZE;
      if (currentGrid[ny][nx]) count++;
    }
  }
  return count;
}

void setup() {
  strip.begin();
  strip.setBrightness(BRIGHTNESS);
  strip.clear();
  strip.show();

  randomSeed(analogRead(0)); // Seed random generator from unused pin noise
  seedGrid();
}

void loop() {
  bool changed = false;
  int totalLive = 0;

  // Render current state to LEDs
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int idx = xyToIndex(x, y);
      if (currentGrid[y][x]) {
        strip.setPixelColor(idx, strip.Color(255, 255, 255)); // Bright cyan/blue live cells
        totalLive++;
      } else {
        strip.setPixelColor(idx, strip.Color(0, 0, 0));       // Off
      }
    }
  }
  strip.show();
  delay(250); // Speed of simulation (250 ms per step)

  // Compute next generation rules
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      int neighbors = countNeighbors(x, y);
      bool alive = currentGrid[y][x];

      if (alive && (neighbors == 2 || neighbors == 3)) {
        nextGrid[y][x] = true;
      } else if (!alive && neighbors == 3) {
        nextGrid[y][x] = true;
      } else {
        nextGrid[y][x] = false;
      }

      if (nextGrid[y][x] != currentGrid[y][x]) {
        changed = true;
      }
    }
  }

  // Copy next generation to current
  for (int y = 0; y < GRID_SIZE; y++) {
    for (int x = 0; x < GRID_SIZE; x++) {
      currentGrid[y][x] = nextGrid[y][x];
    }
  }

  // Auto-restart if all cells die or the simulation reaches a static state
  if (!changed || totalLive == 0) {
    delay(1000); // Pause briefly before restarting
    seedGrid();
  }
}