import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';

enum LedGameMode {
  gameOfLife(0, "Conway's Life", Icons.grain),
  tetris(1, "Tetris (AI)", Icons.smart_toy_outlined),
  rainbow(2, "Rainbow Wave", Icons.palette_outlined),
  customDraw(3, "Drawing Canvas", Icons.draw_outlined);

  final int id;
  final String label;
  final IconData icon;

  const LedGameMode(this.id, this.label, this.icon);

  static LedGameMode fromId(int id) {
    return LedGameMode.values.firstWhere(
      (m) => m.id == id,
      orElse: () => LedGameMode.tetris,
    );
  }
}

class LedMatrixData {
  int activeGame;
  bool isAuto;
  int speedMs;
  int brightness;
  int score;
  int lines;
  bool isRunning;
  int batteryPercent;
  int estimatedCurrentMa;
  int maxCurrentMa;
  bool isPowerLimited;
  List<Color> pixels; // 64 pixels (8x8)
  DateTime lastUpdated;

  static const int gridSize = 8;
  static const int numLeds = 64;
  static const int hardPowerLimitMa = 1000; // Strict 1.0A maximum ceiling

  LedMatrixData({
    this.activeGame = 1,
    this.isAuto = true,
    this.speedMs = 400,
    this.brightness = 20,
    this.score = 0,
    this.lines = 0,
    this.isRunning = true,
    this.batteryPercent = 85,
    this.estimatedCurrentMa = 64,
    this.maxCurrentMa = 1000,
    this.isPowerLimited = false,
    List<Color>? pixels,
    DateTime? lastUpdated,
  })  : pixels = pixels ?? List.generate(numLeds, (_) => Colors.black),
        lastUpdated = lastUpdated ?? DateTime.now();

  LedGameMode get mode => LedGameMode.fromId(activeGame);

  /// Parse telemetry JSON received from ESP32 BLE status characteristic
  bool parseFromStatusJson(String raw) {
    try {
      final trimmed = raw.trim();
      if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return false;
      final Map<String, dynamic> data = jsonDecode(trimmed);

      if (data.containsKey('game')) activeGame = data['game'] as int;
      if (data.containsKey('auto')) isAuto = data['auto'] as bool;
      if (data.containsKey('speed')) speedMs = (data['speed'] as num).toInt();
      if (data.containsKey('bright')) brightness = (data['bright'] as num).toInt();
      if (data.containsKey('score')) score = (data['score'] as num).toInt();
      if (data.containsKey('lines')) lines = (data['lines'] as num).toInt();
      if (data.containsKey('run')) isRunning = data['run'] as bool;
      if (data.containsKey('bat')) batteryPercent = (data['bat'] as num).toInt();
      if (data.containsKey('cur')) estimatedCurrentMa = (data['cur'] as num).toInt();
      if (data.containsKey('max_cur')) maxCurrentMa = (data['max_cur'] as num).toInt();
      if (data.containsKey('pwr_lim')) {
        final val = data['pwr_lim'];
        isPowerLimited = (val is bool) ? val : (val.toString().toLowerCase() == 'true');
      }

      lastUpdated = DateTime.now();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Calculates electrical current draw (mA) for matrix based on current pixel buffer and brightness
  int computeEstimatedCurrentMa({int? brightnessOverride}) {
    if (!isRunning) return 64; // ~1mA baseline per LED quiescent IC draw
    final b = brightnessOverride ?? brightness;
    final bScale = b / 255.0;
    double activeMa = 0.0;
    for (final color in pixels) {
      if (color.a == 0.0 || (color.r == 0.0 && color.g == 0.0 && color.b == 0.0)) {
        continue;
      }
      final rVal = (color.r * 255.0 * bScale);
      final gVal = (color.g * 255.0 * bScale);
      final bVal = (color.b * 255.0 * bScale);
      activeMa += ((rVal + gVal + bVal) / 255.0) * 20.0; // ~20mA per max subpixel channel
    }
    final total = 64.0 + activeMa;
    return total.round().clamp(64, maxCurrentMa);
  }

  /// Parse 64-byte packed matrix frame (RRRGGGBB) from BLE matrix characteristic
  bool parseFromMatrixFrameBytes(List<int> bytes) {
    if (bytes.length < 64) return false;
    for (int i = 0; i < 64; i++) {
      int b = bytes[i];
      // Unpack RRRGGGBB
      int r = ((b >> 5) & 0x07) * 255 ~/ 7;
      int g = ((b >> 2) & 0x07) * 255 ~/ 7;
      int bVal = (b & 0x03) * 255 ~/ 3;

      pixels[i] = (r == 0 && g == 0 && bVal == 0)
          ? Colors.black
          : Color.fromARGB(255, r, g, bVal);
    }
    lastUpdated = DateTime.now();
    return true;
  }

  /// Pack current 64 pixels into 64 bytes (RRRGGGBB)
  List<int> toMatrixFrameBytes() {
    final List<int> bytes = List.filled(64, 0);
    for (int y = 0; y < gridSize; y++) {
      for (int x = 0; x < gridSize; x++) {
        final idx = xyToIndex(x, y);
        final col = idx < pixels.length ? pixels[idx] : Colors.black;
        final r = (col.r * 255.0).round().clamp(0, 255);
        final g = (col.g * 255.0).round().clamp(0, 255);
        final b = (col.b * 255.0).round().clamp(0, 255);
        // Pack into 1 byte: R:3 bits, G:3 bits, B:2 bits
        bytes[y * gridSize + x] = ((r >> 5) << 5) | ((g >> 2) << 2) | (b >> 6);
      }
    }
    return bytes;
  }

  /// Convert 64-byte packed frame to 128-character hexadecimal string
  String toMatrixFrameHex() {
    final bytes = toMatrixFrameBytes();
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString().toUpperCase();
  }

  /// Helper to convert (x, y) to matrix index in serpentine layout
  static int xyToIndex(int x, int y) {
    if (x < 0 || x >= gridSize || y < 0 || y >= gridSize) return 0;
    if (y % 2 == 1) {
      return y * gridSize + (gridSize - 1 - x);
    } else {
      return y * gridSize + x;
    }
  }

  /// Create a sample simulated instance for preview & standalone demo
  factory LedMatrixData.sample() {
    final data = LedMatrixData(
      activeGame: 1,
      isAuto: true,
      speedMs: 400,
      brightness: 20,
      score: 300,
      lines: 3,
      isRunning: true,
      batteryPercent: 88,
      estimatedCurrentMa: 180,
      maxCurrentMa: 1000,
      isPowerLimited: false,
    );
    data._generateSampleTetrisBoard();
    data.estimatedCurrentMa = data.computeEstimatedCurrentMa();
    return data;
  }

  void _generateSampleTetrisBoard() {
    // Fill bottom row with yellow / cyan
    for (int x = 0; x < 8; x++) {
      if (x != 4) {
        pixels[xyToIndex(x, 7)] = const Color(0xFF00FFFF);
      }
      if (x >= 2 && x <= 6) {
        pixels[xyToIndex(x, 6)] = const Color(0xFFFF00FF);
      }
    }
    // Falling piece at top
    pixels[xyToIndex(3, 2)] = const Color(0xFFFFFF00);
    pixels[xyToIndex(4, 2)] = const Color(0xFFFFFF00);
    pixels[xyToIndex(3, 3)] = const Color(0xFFFFFF00);
    pixels[xyToIndex(4, 3)] = const Color(0xFFFFFF00);
  }

  /// Simulation step for standalone demo mode
  void simulateStep(double timeStep) {
    if (!isRunning) {
      estimatedCurrentMa = 64;
      isPowerLimited = false;
      return;
    }

    if (activeGame == 0) {
      // Game of Life simulation pattern
      for (int i = 0; i < 64; i++) {
        final rand = math.Random((timeStep * 10 + i).toInt());
        pixels[i] = rand.nextBool() && rand.nextInt(10) < 4
            ? const Color(0xFF00FF88)
            : Colors.black;
      }
    } else if (activeGame == 1) {
      // Tetris falling simulation
      final int step = (timeStep * 2).toInt() % 7;
      for (int i = 0; i < 64; i++) {
        pixels[i] = Colors.black;
      }
      // Fixed blocks on ground
      pixels[xyToIndex(0, 7)] = const Color(0xFF00FFFF);
      pixels[xyToIndex(1, 7)] = const Color(0xFF00FFFF);
      pixels[xyToIndex(6, 7)] = const Color(0xFFFF00FF);
      pixels[xyToIndex(7, 7)] = const Color(0xFFFF00FF);

      // Moving piece
      final int py = (step).clamp(0, 6);
      pixels[xyToIndex(3, py)] = const Color(0xFFFFFF00);
      pixels[xyToIndex(4, py)] = const Color(0xFFFFFF00);
      pixels[xyToIndex(3, py + 1)] = const Color(0xFFFFFF00);
      pixels[xyToIndex(4, py + 1)] = const Color(0xFFFFFF00);
    } else if (activeGame == 2) {
      // Rainbow simulation
      for (int y = 0; y < gridSize; y++) {
        for (int x = 0; x < gridSize; x++) {
          final double hue = ((timeStep * 40) + (x * 20) + (y * 20)) % 360;
          pixels[xyToIndex(x, y)] = HSLColor.fromAHSL(1.0, hue, 1.0, 0.5).toColor();
        }
      }
    }

    estimatedCurrentMa = computeEstimatedCurrentMa();
    isPowerLimited = estimatedCurrentMa >= maxCurrentMa;
    lastUpdated = DateTime.now();
  }
}
