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
import 'package:esp32_project_cotroller/models/led_matrix_data.dart';
import 'package:esp32_project_cotroller/widgets/battery_visualizer.dart';
import 'package:esp32_project_cotroller/widgets/soil_visualizer.dart';
import 'package:esp32_project_cotroller/widgets/sensor_chart.dart';
import 'package:esp32_project_cotroller/widgets/led_matrix_display.dart';
import 'package:esp32_project_cotroller/widgets/gamepad_controller.dart';
import 'package:esp32_project_cotroller/screens/visualisations_screen.dart';
import 'package:esp32_project_cotroller/screens/led_controller_screen.dart';

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

  test('LedMatrixData parses JSON status and matrix frame correctly', () {
    final ledData = LedMatrixData();
    const statusJson = '{"game":1,"auto":true,"speed":350,"bright":25,"score":450,"lines":4,"run":true,"bat":92,"cur":340,"max_cur":1000,"pwr_lim":false}';
    expect(ledData.parseFromStatusJson(statusJson), isTrue);
    expect(ledData.activeGame, equals(1));
    expect(ledData.isAuto, isTrue);
    expect(ledData.speedMs, equals(350));
    expect(ledData.brightness, equals(25));
    expect(ledData.score, equals(450));
    expect(ledData.lines, equals(4));
    expect(ledData.isRunning, isTrue);
    expect(ledData.batteryPercent, equals(92));
    expect(ledData.estimatedCurrentMa, equals(340));
    expect(ledData.maxCurrentMa, equals(1000));
    expect(ledData.isPowerLimited, isFalse);

    // Test matrix frame bytes parsing
    final dummyFrame = List.generate(64, (i) => 0xE0); // Red
    expect(ledData.parseFromMatrixFrameBytes(dummyFrame), isTrue);
    expect(ledData.pixels[0].r, greaterThan(0.9));

    // Test matrix frame packing to bytes and hex
    final packedBytes = ledData.toMatrixFrameBytes();
    expect(packedBytes.length, equals(64));
    expect(packedBytes[0], equals(0xE0)); // R:3 bits (111), G:3 bits (000), B:2 bits (00) -> 0xE0
    final hexString = ledData.toMatrixFrameHex();
    expect(hexString.length, equals(128));
    expect(hexString.startsWith('E0'), isTrue);
  });

  test('LedMatrixData enforces 1.0A power calculation and clamping', () {
    final ledData = LedMatrixData(brightness: 255, isRunning: true);
    // Fill all 64 pixels with full white
    ledData.pixels = List.generate(64, (_) => const Color(0xFFFFFFFF));
    final current = ledData.computeEstimatedCurrentMa();
    // Peak theoretical for 64 white LEDs at 255 would be ~3900mA, clamped to maxCurrentMa (1000mA)
    expect(current, equals(1000));
    expect(current, lessThanOrEqualTo(LedMatrixData.hardPowerLimitMa));

    // When LEDs are dark or display is paused
    ledData.isRunning = false;
    expect(ledData.computeEstimatedCurrentMa(), equals(64)); // baseline quiescent
  });

  testWidgets('GamepadController renders power monitor and current draw', (WidgetTester tester) async {
    final ledData = LedMatrixData.sample();
    ledData.estimatedCurrentMa = 380;
    ledData.maxCurrentMa = 1000;
    ledData.isPowerLimited = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamepadController(
            data: ledData,
            onSendCommand: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Current Draw: 380 mA / 1000 mA'), findsOneWidget);
    expect(find.textContaining('1.0A Safe'), findsOneWidget);
    expect(find.textContaining('Hardware protection ceiling strictly enforced at 1.0A'), findsOneWidget);
  });

  testWidgets('LedMatrixDisplay renders canvas and supports drawing', (WidgetTester tester) async {
    final ledData = LedMatrixData.sample();
    int? drawnX;
    int? drawnY;
    Color? drawnColor;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LedMatrixDisplay(
            data: ledData,
            isInteractiveDraw: true,
            selectedDrawColor: const Color(0xFFFF0000),
            onPixelDrawn: (x, y, color) {
              drawnX = x;
              drawnY = y;
              drawnColor = color;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LedMatrixDisplay), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);

    // Tap on top left corner (pixel 0,0)
    await tester.tapAt(tester.getTopLeft(find.byType(CustomPaint).first) + const Offset(15, 15));
    await tester.pumpAndSettle();

    expect(drawnX, equals(0));
    expect(drawnY, equals(0));
    expect(drawnColor, equals(const Color(0xFFFF0000)));
  });

  testWidgets('GamepadController dispatches mode and action commands', (WidgetTester tester) async {
    final ledData = LedMatrixData.sample();
    final List<String> sentCommands = [];
    bool boardSent = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GamepadController(
            data: ledData,
            onSendCommand: (cmd) => sentCommands.add(cmd),
            onSendBoard: () => boardSent = true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify chips
    expect(find.text("Conway's Life"), findsOneWidget);
    expect(find.text("Tetris (AI)"), findsOneWidget);
    expect(find.text("Rainbow Wave"), findsOneWidget);
    expect(find.text("Drawing Canvas"), findsOneWidget);

    // Tap Reset Board in AI Tetris Card
    await tester.tap(find.text('Reset Board'));
    await tester.pumpAndSettle();
    expect(sentCommands, contains('RESET'));

    // Tap Mode Chip for Game of Life
    await tester.tap(find.text("Conway's Life"));
    await tester.pumpAndSettle();
    expect(sentCommands, contains('GAME:0'));

    // Test Custom Command Console
    final cmdInput = find.widgetWithText(TextField, 'e.g. SPEED:250, GLIDER, BRIGHT:100');
    expect(cmdInput, findsOneWidget);
    await tester.enterText(cmdInput, 'SPEED:180');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
    await tester.pumpAndSettle();
    expect(sentCommands, contains('SPEED:180'));

    // Tap preset chip 'GLIDER'
    await tester.tap(find.widgetWithText(ActionChip, 'GLIDER'));
    await tester.pumpAndSettle();
    expect(sentCommands, contains('GLIDER'));

    // Switch to Drawing Canvas mode and verify 'Send to Matrix'
    await tester.tap(find.text("Drawing Canvas"));
    await tester.pumpAndSettle();
    expect(sentCommands, contains('GAME:3'));

    await tester.tap(find.widgetWithText(ElevatedButton, 'Send to Matrix'));
    await tester.pumpAndSettle();
    expect(boardSent, isTrue);
  });

  testWidgets('LedControllerScreen renders in standalone simulation mode', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LedControllerScreen(
          isStandaloneDemo: true,
          displayName: 'LED Demo Test',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LED Demo Test'), findsOneWidget);
    expect(find.text('Interactive Simulation Mode'), findsOneWidget);
    expect(find.byType(LedMatrixDisplay), findsOneWidget);
    expect(find.byType(GamepadController), findsOneWidget);
  });
}
