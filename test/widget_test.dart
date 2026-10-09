// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:esp32_project_cotroller/main.dart';
import 'package:esp32_project_cotroller/models/sensor_data.dart';
import 'package:esp32_project_cotroller/widgets/battery_visualizer.dart';
import 'package:esp32_project_cotroller/widgets/soil_visualizer.dart';
import 'package:esp32_project_cotroller/widgets/sensor_chart.dart';
import 'package:esp32_project_cotroller/screens/visualisations_screen.dart';

final class FakeFlutterBluePlusPlatform extends FlutterBluePlusPlatform {
  final StreamController<BmBluetoothAdapterState> _adapterStateController =
      StreamController<BmBluetoothAdapterState>.broadcast();
  final StreamController<BmScanResponse> _scanResponseController =
      StreamController<BmScanResponse>.broadcast();
  final StreamController<BmConnectionStateResponse> _connectionStateController =
      StreamController<BmConnectionStateResponse>.broadcast();

  @override
  Stream<BmBluetoothAdapterState> get onAdapterStateChanged => _adapterStateController.stream;

  @override
  Stream<BmScanResponse> get onScanResponse => _scanResponseController.stream;

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged => _connectionStateController.stream;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(BmBluetoothAdapterStateRequest request) async {
    return BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);
  }

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async {
    return true;
  }

  @override
  Future<bool> startScan(BmScanSettings request) async {
    return true;
  }

  @override
  Future<bool> stopScan(BmStopScanRequest request) async {
    return true;
  }

  @override
  Future<bool> setLogLevel(BmSetLogLevelRequest request) async {
    return true;
  }

  @override
  Future<bool> connect(BmConnectRequest request) async {
    return true;
  }

  @override
  Future<bool> disconnect(BmDisconnectRequest request) async {
    return true;
  }
}

void main() {
  late FakeFlutterBluePlusPlatform fakePlatform;

  setUp(() {
    fakePlatform = FakeFlutterBluePlusPlatform();
    FlutterBluePlusPlatform.instance = fakePlatform;
  });

  testWidgets('App renders BLE Scanner title and scan controls', (WidgetTester tester) async {
    await tester.pumpWidget(const Esp32BleApp());
    await tester.pumpAndSettle();

    // Verify app title appears
    expect(find.text('XIAO ESP32-C5 BLE'), findsOneWidget);
    // Verify scan chip or button exists
    expect(find.text('XIAO / ESP32'), findsOneWidget);
    expect(find.text('Scan BLE'), findsOneWidget);
  });

  testWidgets('Search input updates filter', (WidgetTester tester) async {
    await tester.pumpWidget(const Esp32BleApp());
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    expect(searchField, findsOneWidget);

    await tester.enterText(searchField, 'ESP32');
    await tester.pumpAndSettle();

    expect(find.text('ESP32'), findsOneWidget);
  });

  testWidgets('Tapping XIAO / ESP32 chip sets search filter', (WidgetTester tester) async {
    await tester.pumpWidget(const Esp32BleApp());
    await tester.pumpAndSettle();

    final chip = find.text('XIAO / ESP32');
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('xiao'), findsOneWidget);
  });

  test('SensorData parses JSON telemetry payload from ESP32 BLE', () {
    final sensor = SensorData();
    const jsonPayload = '{"bat_v":3.845,"bat_pct":70.4,"soil_pct":55.2,"soil_v":1.32,"soil_raw":1638}';
    final success = sensor.parseFromRaw(jsonPayload);

    expect(success, isTrue);
    expect(sensor.batteryVoltage, closeTo(3.845, 0.001));
    expect(sensor.batteryPercent, closeTo(70.4, 0.1));
    expect(sensor.soilPercent, closeTo(55.2, 0.1));
    expect(sensor.soilVoltage, closeTo(1.32, 0.01));
    expect(sensor.soilRaw, equals(1638));
    expect(sensor.history.length, equals(1));
  });

  test('SensorData parses Arduino serial formatted string', () {
    final sensor = SensorData();
    const serialStr = 'Battery: 3.845 V (70.0%) | Soil: 55.4% (Voltage: 1.32V, Raw: 1638, Measured: 1.50V, Supply: 3.75V)';
    final success = sensor.parseFromRaw(serialStr);

    expect(success, isTrue);
    expect(sensor.batteryVoltage, closeTo(3.845, 0.001));
    expect(sensor.batteryPercent, closeTo(70.0, 0.1));
    expect(sensor.soilPercent, closeTo(55.4, 0.1));
    expect(sensor.soilVoltage, closeTo(1.32, 0.01));
    expect(sensor.soilRaw, equals(1638));
  });

  test('SensorData parses single-byte BLE battery level', () {
    final sensor = SensorData();
    sensor.parseFromBatteryLevelBytes([85]); // 85%

    expect(sensor.batteryPercent, equals(85.0));
  });

  testWidgets('BatteryVisualizer renders cell, gauge, and details styles', (WidgetTester tester) async {
    final data = SensorData(batteryPercent: 75.0, batteryVoltage: 3.90);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: BatteryVisualizer(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default is Cell
    expect(find.text('Battery Level Visualisation'), findsOneWidget);
    expect(find.text('75.0%'), findsOneWidget);
    expect(find.text('3.900 V'), findsOneWidget);

    // Switch to Gauge
    await tester.tap(find.text('Gauge'));
    await tester.pumpAndSettle();
    expect(find.text('Radial Battery Gauge'), findsOneWidget);

    // Switch to Details
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Battery Diagnostics & Curve'), findsOneWidget);
    expect(find.text('LiPo / Li-Ion (1S Single Cell)'), findsOneWidget);
  });

  testWidgets('SoilVisualizer renders pot, gauge, and calibration styles', (WidgetTester tester) async {
    final data = SensorData(soilPercent: 60.0, soilVoltage: 1.28, soilRaw: 1588);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SoilVisualizer(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default is Soil Pot
    expect(find.text('Soil Capacitive Moisture'), findsOneWidget);
    expect(find.text('60.0%'), findsWidgets);
    expect(find.text('SEN0193 Probe'), findsOneWidget);

    // Switch to Gauge
    await tester.tap(find.text('Gauge'));
    await tester.pumpAndSettle();
    expect(find.text('Soil Moisture Gauge'), findsOneWidget);

    // Switch to Sensor / Cal
    await tester.tap(find.text('Sensor / Cal'));
    await tester.pumpAndSettle();
    expect(find.text('Capacitive Sensor Calibration'), findsOneWidget);
    expect(find.text('DFRobot SEN0193 / Analog Capacitive'), findsOneWidget);
    expect(find.text('Dry Air Calibration (SOIL_DRY_VOLT)'), findsOneWidget);
  });

  testWidgets('SensorTrendChart renders chart with history points', (WidgetTester tester) async {
    final data = SensorData.sample();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SensorTrendChart(data: data),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Live Sensor Telemetry Trends'), findsOneWidget);
    expect(find.text('Soil Moisture %'), findsOneWidget);
    expect(find.text('Battery %'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('VisualisationsScreen opens and navigates between tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VisualisationsScreen(
          isStandaloneDemo: false,
          displayName: 'Test Device',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Device'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Battery'), findsOneWidget);
    expect(find.text('Soil Moisture'), findsOneWidget);
    expect(find.text('Trends'), findsOneWidget);

    // Navigate to Battery tab
    await tester.tap(find.text('Battery'));
    await tester.pumpAndSettle();
    expect(find.text('Battery Historical Curve'), findsOneWidget);

    // Navigate to Soil Moisture tab
    await tester.tap(find.text('Soil Moisture'));
    await tester.pumpAndSettle();
    expect(find.text('Sensor Calibration'), findsOneWidget);

    // Navigate to Trends tab
    await tester.tap(find.text('Trends'));
    await tester.pumpAndSettle();
    expect(find.text('Combined Multi-Sensor Telemetry'), findsOneWidget);
    expect(find.text('Telemetry Statistics'), findsOneWidget);
  });

  test('SensorData calibration methods and percent calculation', () {
    final sensor = SensorData(soilVoltage: 1.365);
    // Default calibration: dry = 1.78, wet = 0.95
    expect(sensor.dryVolt, equals(1.78));
    expect(sensor.wetVolt, equals(0.95));
    expect(sensor.soilPercent, closeTo(50.0, 0.5));

    // Custom 2-point calibration
    sensor.setCalibration(2.0, 1.0);
    expect(sensor.dryVolt, equals(2.0));
    expect(sensor.wetVolt, equals(1.0));
    // At 1.365V: (2.0 - 1.365) / (2.0 - 1.0) * 100 = 63.5%
    expect(sensor.soilPercent, closeTo(63.5, 0.1));

    // Calibrate dry point with current voltage (1.365V -> 0% moisture)
    sensor.calibrateDry();
    expect(sensor.dryVolt, equals(1.365));
    expect(sensor.soilPercent, closeTo(0.0, 0.1));

    // Reset calibration
    sensor.resetCalibration();
    expect(sensor.dryVolt, equals(1.78));
    expect(sensor.wetVolt, equals(0.95));
  });

  test('SensorData parses JSON and serial calibration parameters', () {
    final sensor = SensorData();
    const jsonWithCal = '{"bat_v":3.85,"bat_pct":75.0,"soil_pct":50.0,"soil_v":1.365,"dry_v":1.85,"wet_v":0.88}';
    expect(sensor.parseFromRaw(jsonWithCal), isTrue);
    expect(sensor.dryVolt, equals(1.85));
    expect(sensor.wetVolt, equals(0.88));

    const serialWithCal = 'Battery: 3.850 V (75.0%) | Soil: 50.0% (Voltage: 1.36V, Raw: 1690, Dry: 1.90V, Wet: 0.90V, Measured: 1.36V, Supply: 3.30V)';
    expect(sensor.parseFromRaw(serialWithCal), isTrue);
    expect(sensor.dryVolt, equals(1.90));
    expect(sensor.wetVolt, equals(0.90));
  });

  testWidgets('SoilVisualizer calibration card allows one-click calibration and fine tuning', (WidgetTester tester) async {
    final data = SensorData(soilVoltage: 1.30, soilPercent: 55.0);
    bool dryCalibrated = false;
    bool wetCalibrated = false;
    bool resetCalled = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SoilVisualizer(
              data: data,
              initialStyle: SoilVisualizerStyle.calibration,
              onCalibrateCurrentDry: () => dryCalibrated = true,
              onCalibrateCurrentWet: () => wetCalibrated = true,
              onResetCalibration: () => resetCalled = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Capacitive Sensor Calibration'), findsOneWidget);
    expect(find.text('Set as Dry (0%)'), findsOneWidget);
    expect(find.text('Set as Wet (100%)'), findsOneWidget);
    expect(find.text('Tune & Presets'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);

    // Test tap Dry
    await tester.tap(find.text('Set as Dry (0%)'));
    await tester.pumpAndSettle();
    expect(dryCalibrated, isTrue);

    // Test tap Wet
    await tester.tap(find.text('Set as Wet (100%)'));
    await tester.pumpAndSettle();
    expect(wetCalibrated, isTrue);

    // Test tap Reset
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(resetCalled, isTrue);

    // Test open Tuning Sheet
    await tester.tap(find.text('Tune & Presets'));
    await tester.pumpAndSettle();
    expect(find.text('Sensor Calibration Options'), findsOneWidget);
    expect(find.text('SEN0193 (1.78V / 0.95V)'), findsOneWidget);
    expect(find.text('3.3V Resistive (3.00V / 1.20V)'), findsOneWidget);
    expect(find.text('Apply Calibration'), findsOneWidget);
  });

  testWidgets('VisualisationsScreen measurement switch toggles on and off', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: VisualisationsScreen(
          isStandaloneDemo: true,
          displayName: 'Demo Device',
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Default: measurement is on and demo simulation is active
    expect(find.text('Demo Simulation Active'), findsOneWidget);
    expect(find.text('SIMULATED'), findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    // Toggle switch OFF
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(find.text('Measurements: PAUSED (OFF)'), findsOneWidget);

    // Toggle switch back ON
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(find.text('Demo Simulation Active'), findsOneWidget);
  });

  testWidgets('DeviceDetailScreen renders tabs and visualisations', (WidgetTester tester) async {
    final device = BluetoothDevice.fromId('AA:BB:CC:DD:EE:FF');

    await tester.pumpWidget(
      MaterialApp(
        home: DeviceDetailScreen(
          device: device,
          displayName: 'Test XIAO ESP32-C5',
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 16));

    expect(find.text('Test XIAO ESP32-C5'), findsOneWidget);
    expect(find.text('AA:BB:CC:DD:EE:FF'), findsOneWidget);
    expect(find.text('Visualisations'), findsOneWidget);
    expect(find.text('Services & GATT'), findsOneWidget);
    expect(find.text('Console Log'), findsOneWidget);
  });
}
