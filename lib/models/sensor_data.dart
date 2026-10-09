import 'dart:convert';

class SensorDataPoint {
  final DateTime timestamp;
  final double? batteryVoltage;
  final double? batteryPercent;
  final double? soilPercent;
  final double? soilVoltage;
  final int? soilRaw;

  SensorDataPoint({
    required this.timestamp,
    this.batteryVoltage,
    this.batteryPercent,
    this.soilPercent,
    this.soilVoltage,
    this.soilRaw,
  });
}

class SensorData {
  double? batteryVoltage; // e.g., 3.85 V
  double? batteryPercent; // 0 - 100 %
  double? soilPercent; // 0 - 100 % (Moisture)
  double? soilVoltage; // e.g., 1.42 V (SEN0193 capacitive sensor)
  int? soilRaw; // 0 - 4095
  double dryVolt; // Dry air reference voltage (default 1.78 V -> 0% moisture)
  double wetVolt; // 100% water reference voltage (default 0.95 V -> 100% moisture)
  DateTime lastUpdated;
  final List<SensorDataPoint> history;

  static const double defaultDryVolt = 1.78;
  static const double defaultWetVolt = 0.95;
  static const int maxHistoryLength = 60;

  SensorData({
    this.batteryVoltage,
    this.batteryPercent,
    this.soilPercent,
    this.soilVoltage,
    this.soilRaw,
    this.dryVolt = defaultDryVolt,
    this.wetVolt = defaultWetVolt,
    DateTime? lastUpdated,
    List<SensorDataPoint>? history,
  })  : lastUpdated = lastUpdated ?? DateTime.now(),
        history = history ?? [] {
    if (soilPercent == null && soilVoltage != null) {
      soilPercent = calculateSoilPercent(soilVoltage!);
    }
  }

  /// Calculate soil moisture percentage using current calibration thresholds
  double calculateSoilPercent(double voltage) {
    final diff = dryVolt - wetVolt;
    if (diff.abs() < 0.0001) return 0.0;
    return ((dryVolt - voltage) / diff * 100.0).clamp(0.0, 100.0);
  }

  /// Calibrate the dry point (0% moisture) to current or given voltage
  void calibrateDry([double? voltage]) {
    final v = voltage ?? soilVoltage ?? dryVolt;
    dryVolt = v;
    if (soilVoltage != null) {
      soilPercent = calculateSoilPercent(soilVoltage!);
    }
    lastUpdated = DateTime.now();
  }

  /// Calibrate the wet point (100% moisture) to current or given voltage
  void calibrateWet([double? voltage]) {
    final v = voltage ?? soilVoltage ?? wetVolt;
    wetVolt = v;
    if (soilVoltage != null) {
      soilPercent = calculateSoilPercent(soilVoltage!);
    }
    lastUpdated = DateTime.now();
  }

  /// Set both calibration thresholds simultaneously
  void setCalibration(double dry, double wet) {
    dryVolt = dry;
    wetVolt = wet;
    if (soilVoltage != null) {
      soilPercent = calculateSoilPercent(soilVoltage!);
    }
    lastUpdated = DateTime.now();
  }

  /// Reset calibration parameters to default factory specifications
  void resetCalibration() {
    dryVolt = defaultDryVolt;
    wetVolt = defaultWetVolt;
    if (soilVoltage != null) {
      soilPercent = calculateSoilPercent(soilVoltage!);
    }
    lastUpdated = DateTime.now();
  }

  /// Create a mock/sample sensor data instance for demo / testing
  factory SensorData.sample() {
    final now = DateTime.now();
    final data = SensorData(
      batteryVoltage: 3.84,
      batteryPercent: 70.0,
      soilPercent: 55.4,
      soilVoltage: 1.32,
      soilRaw: 1638,
      dryVolt: 1.78,
      wetVolt: 0.95,
      lastUpdated: now,
    );

    // Populate some initial history points for nice charts
    for (int i = 20; i >= 0; i--) {
      final t = now.subtract(Duration(seconds: i * 2));
      final double sinVal = (i % 10) / 10.0;
      data.history.add(SensorDataPoint(
        timestamp: t,
        batteryVoltage: 3.84 - (i * 0.001),
        batteryPercent: 70.0 - (i * 0.1),
        soilPercent: (55.0 + sinVal * 8.0).clamp(0.0, 100.0),
        soilVoltage: (1.32 - sinVal * 0.08).clamp(0.95, 1.78),
        soilRaw: (1638 - (sinVal * 100).toInt()),
      ));
    }
    return data;
  }

  void update({
    double? newBatteryVoltage,
    double? newBatteryPercent,
    double? newSoilPercent,
    double? newSoilVoltage,
    int? newSoilRaw,
    double? newDryVolt,
    double? newWetVolt,
  }) {
    if (newDryVolt != null) dryVolt = newDryVolt;
    if (newWetVolt != null) wetVolt = newWetVolt;

    if (newBatteryVoltage != null) batteryVoltage = newBatteryVoltage;
    if (newBatteryPercent != null) {
      batteryPercent = newBatteryPercent.clamp(0.0, 100.0);
    } else if (newBatteryVoltage != null) {
      // Calculate battery percent from voltage (3.0V - 4.2V range)
      batteryPercent = ((newBatteryVoltage - 3.0) / (4.2 - 3.0) * 100.0).clamp(0.0, 100.0);
    }

    if (newSoilPercent != null) {
      soilPercent = newSoilPercent.clamp(0.0, 100.0);
    }
    if (newSoilVoltage != null) {
      soilVoltage = newSoilVoltage;
      if (newSoilPercent == null) {
        soilPercent = calculateSoilPercent(newSoilVoltage);
      }
    }
    if (newSoilRaw != null) {
      soilRaw = newSoilRaw;
      if (soilVoltage == null && newSoilVoltage == null) {
        soilVoltage = newSoilRaw * (3.3 / 4095.0);
        if (newSoilPercent == null && soilPercent == null) {
          soilPercent = calculateSoilPercent(soilVoltage!);
        }
      }
    }

    lastUpdated = DateTime.now();

    // Append to history
    history.add(SensorDataPoint(
      timestamp: lastUpdated,
      batteryVoltage: batteryVoltage,
      batteryPercent: batteryPercent,
      soilPercent: soilPercent,
      soilVoltage: soilVoltage,
      soilRaw: soilRaw,
    ));

    if (history.length > maxHistoryLength) {
      history.removeAt(0);
    }
  }

  /// Parses incoming strings from BLE characteristics (JSON, serial logs, or key-value)
  bool parseFromRaw(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return false;

    // 1. Try JSON parsing
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed) as Map<String, dynamic>;
        double? batV = _toDouble(map['bat_v'] ?? map['battery_voltage'] ?? map['battery_v'] ?? map['vbatt']);
        double? batPct = _toDouble(map['bat_pct'] ?? map['battery_percent'] ?? map['battery_pct'] ?? map['bat']);
        double? soilPct = _toDouble(map['soil_pct'] ?? map['soil_percent'] ?? map['soil'] ?? map['moisture']);
        double? soilV = _toDouble(map['soil_v'] ?? map['soil_voltage'] ?? map['soil_volt']);
        int? soilR = _toInt(map['soil_raw'] ?? map['sensor_value'] ?? map['raw']);
        double? dryV = _toDouble(map['dry_v'] ?? map['dry_volt'] ?? map['cal_dry']);
        double? wetV = _toDouble(map['wet_v'] ?? map['wet_volt'] ?? map['cal_wet']);

        update(
          newBatteryVoltage: batV,
          newBatteryPercent: batPct,
          newSoilPercent: soilPct,
          newSoilVoltage: soilV,
          newSoilRaw: soilR,
          newDryVolt: dryV,
          newWetVolt: wetV,
        );
        return true;
      } catch (_) {}
    }

    // 2. Try Regex matching for Arduino Serial formatted string:
    // e.g., "Battery: 3.845 V (70.0%) | Soil: 55.4% (Voltage: 1.32V, Raw: 1638, Dry: 1.78V, Wet: 0.95V, Measured: 1.50V, Supply: 3.75V)"
    final serialBatMatch = RegExp(r'Battery:\s*([\d.]+)\s*V\s*\(([\d.]+)\s*%\)', caseSensitive: false).firstMatch(trimmed);
    final serialSoilMatch = RegExp(r'Soil:\s*([\d.]+)\s*%\s*\(Voltage:\s*([\d.]+)\s*V(?:,\s*Raw:\s*(\d+))?(?:,\s*Dry:\s*([\d.]+)V)?(?:,\s*Wet:\s*([\d.]+)V)?.*?\)', caseSensitive: false).firstMatch(trimmed);

    if (serialBatMatch != null || serialSoilMatch != null) {
      double? batV = serialBatMatch != null ? double.tryParse(serialBatMatch.group(1)!) : null;
      double? batPct = serialBatMatch != null ? double.tryParse(serialBatMatch.group(2)!) : null;
      double? soilPct = serialSoilMatch != null ? double.tryParse(serialSoilMatch.group(1)!) : null;
      double? soilV = serialSoilMatch != null ? double.tryParse(serialSoilMatch.group(2)!) : null;
      int? soilR = (serialSoilMatch != null && serialSoilMatch.group(3) != null) ? int.tryParse(serialSoilMatch.group(3)!) : null;
      double? dryV = (serialSoilMatch != null && serialSoilMatch.group(4) != null) ? double.tryParse(serialSoilMatch.group(4)!) : null;
      double? wetV = (serialSoilMatch != null && serialSoilMatch.group(5) != null) ? double.tryParse(serialSoilMatch.group(5)!) : null;

      update(
        newBatteryVoltage: batV,
        newBatteryPercent: batPct,
        newSoilPercent: soilPct,
        newSoilVoltage: soilV,
        newSoilRaw: soilR,
        newDryVolt: dryV,
        newWetVolt: wetV,
      );
      return true;
    }

    // 3. Try key-value or simple numeric values
    // e.g. "soil: 45.2" or "bat: 80" or "dry: 1.78"
    bool matched = false;
    final batPctMatch = RegExp(r'(?:bat|battery)(?:_pct|_level|_percent)?\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);
    final batVMatch = RegExp(r'(?:bat|battery)?_?v(?:olt|oltage)?\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);
    final soilPctMatch = RegExp(r'(?:soil|moisture)(?:_pct|_percent)?\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);
    final soilVMatch = RegExp(r'soil_?v(?:olt|oltage)?\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);
    final dryMatch = RegExp(r'(?:dry|dry_v|cal_dry)\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);
    final wetMatch = RegExp(r'(?:wet|wet_v|cal_wet)\s*[:=]\s*([\d.]+)', caseSensitive: false).firstMatch(trimmed);

    double? batPct = batPctMatch != null ? double.tryParse(batPctMatch.group(1)!) : null;
    double? batV = batVMatch != null ? double.tryParse(batVMatch.group(1)!) : null;
    double? soilPct = soilPctMatch != null ? double.tryParse(soilPctMatch.group(1)!) : null;
    double? soilV = soilVMatch != null ? double.tryParse(soilVMatch.group(1)!) : null;
    double? dryV = dryMatch != null ? double.tryParse(dryMatch.group(1)!) : null;
    double? wetV = wetMatch != null ? double.tryParse(wetMatch.group(1)!) : null;

    if (batPct != null || batV != null || soilPct != null || soilV != null || dryV != null || wetV != null) {
      update(
        newBatteryVoltage: batV,
        newBatteryPercent: batPct,
        newSoilPercent: soilPct,
        newSoilVoltage: soilV,
        newDryVolt: dryV,
        newWetVolt: wetV,
      );
      matched = true;
    }

    return matched;
  }

  /// Update from standard 1-byte BLE battery level (0-100)
  void parseFromBatteryLevelBytes(List<int> bytes) {
    if (bytes.isNotEmpty) {
      final level = bytes[0].toDouble();
      update(newBatteryPercent: level);
    }
  }

  static double? _toDouble(dynamic val) {
    if (val == null) return null;
    if (val is num) return val.toDouble();
    if (val is String) return double.tryParse(val);
    return null;
  }

  static int? _toInt(dynamic val) {
    if (val == null) return null;
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }
}
