import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/sensor_data.dart';
import '../widgets/battery_visualizer.dart';
import '../widgets/soil_visualizer.dart';
import '../widgets/sensor_chart.dart';

class VisualisationsScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final String? displayName;
  final SensorData? initialData;
  final bool isStandaloneDemo;

  const VisualisationsScreen({
    super.key,
    this.device,
    this.displayName,
    this.initialData,
    this.isStandaloneDemo = false,
  });

  @override
  State<VisualisationsScreen> createState() => _VisualisationsScreenState();
}

class _VisualisationsScreenState extends State<VisualisationsScreen> with SingleTickerProviderStateMixin {
  late SensorData _sensorData;
  late TabController _tabController;
  bool _measurementsEnabled = true;
  bool _isSimulating = false;
  Timer? _simulationTimer;
  double _simStep = 0;

  // Auto BLE subscription state
  bool _isAutoSubscribed = false;
  final List<StreamSubscription> _bleSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _sensorData = widget.initialData ?? (widget.isStandaloneDemo ? SensorData.sample() : SensorData());
    _tabController = TabController(length: 4, vsync: this);

    // Assume measurements are always running by default
    if (widget.device != null) {
      _autoSubscribeBle();
    } else if (widget.isStandaloneDemo) {
      _startSimulation();
    }
  }

  @override
  void dispose() {
    _simulationTimer?.cancel();
    for (var sub in _bleSubscriptions) {
      sub.cancel();
    }
    _tabController.dispose();
    super.dispose();
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    setState(() => _isSimulating = true);

    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (!mounted) return;
      _simStep += 0.2;
      final double sinVal = (math.sin(_simStep) + 1.0) / 2.0; // 0.0 to 1.0

      // Simulate battery slowly discharging & fluctuating
      final double simulatedBatPct = (75.0 + math.cos(_simStep * 0.5) * 15.0).clamp(5.0, 100.0);
      final double simulatedBatV = 3.0 + (simulatedBatPct / 100.0) * 1.2;

      // Simulate soil moisture changes
      final double simulatedSoilPct = (sinVal * 85.0 + 10.0).clamp(0.0, 100.0);
      final double simulatedSoilV = 1.78 - (simulatedSoilPct / 100.0) * (1.78 - 0.95);
      final int simulatedSoilRaw = ((simulatedSoilV / 3.3) * 4095).toInt();

      setState(() {
        _sensorData.update(
          newBatteryPercent: simulatedBatPct,
          newBatteryVoltage: simulatedBatV,
          newSoilPercent: simulatedSoilPct,
          newSoilVoltage: simulatedSoilV,
          newSoilRaw: simulatedSoilRaw,
        );
      });
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    setState(() => _isSimulating = false);
  }

  Future<void> _sendBleCommand(String cmd) async {
    if (widget.device == null) return;
    try {
      final services = await widget.device!.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            final uuidLower = c.uuid.toString().toLowerCase();
            final sUuidLower = s.uuid.toString().toLowerCase();
            if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
              await c.write(utf8.encode(cmd), withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
              return;
            }
          }
        }
      }
    } catch (_) {}
  }

  void _calibrateDry() {
    setState(() {
      _sensorData.calibrateDry();
    });
    _sendBleCommand('CAL_DRY');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calibrated DRY point (0% moisture) to ${(_sensorData.soilVoltage ?? _sensorData.dryVolt).toStringAsFixed(2)} V'),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _calibrateWet() {
    setState(() {
      _sensorData.calibrateWet();
    });
    _sendBleCommand('CAL_WET');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Calibrated WET point (100% moisture) to ${(_sensorData.soilVoltage ?? _sensorData.wetVolt).toStringAsFixed(2)} V'),
        backgroundColor: Colors.blueAccent,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _saveCalibration(double dry, double wet) {
    setState(() {
      _sensorData.setCalibration(dry, wet);
    });
    _sendBleCommand('CAL:${dry.toStringAsFixed(2)},${wet.toStringAsFixed(2)}');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Saved Calibration: Dry=${dry.toStringAsFixed(2)}V, Wet=${wet.toStringAsFixed(2)}V'),
        backgroundColor: Colors.teal,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _resetCalibration() {
    setState(() {
      _sensorData.resetCalibration();
    });
    _sendBleCommand('CAL_RESET');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sensor calibration reset to factory defaults (1.78V / 0.95V)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _toggleMeasurements(bool enabled) {
    setState(() => _measurementsEnabled = enabled);
    if (widget.device != null) {
      if (enabled) {
        _autoSubscribeBle();
      } else {
        _unsubscribeBle();
      }
    } else if (widget.isStandaloneDemo) {
      if (enabled) {
        _startSimulation();
      } else {
        _stopSimulation();
      }
    }
  }

  void _unsubscribeBle() {
    if (widget.device != null) {
      widget.device!.discoverServices().then((services) {
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.write || c.properties.writeWithoutResponse) {
              final uuidLower = c.uuid.toString().toLowerCase();
              final sUuidLower = s.uuid.toString().toLowerCase();
              if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
                try {
                  c.write(utf8.encode('OFF'), withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
                } catch (_) {}
              }
            }
          }
        }
      }).catchError((_) {});
    }
    for (var sub in _bleSubscriptions) {
      sub.cancel();
    }
    _bleSubscriptions.clear();
    setState(() => _isAutoSubscribed = false);
  }

  Future<void> _autoSubscribeBle() async {
    if (widget.device == null || !_measurementsEnabled) return;
    try {
      setState(() => _isAutoSubscribed = true);
      final services = await widget.device!.discoverServices();

      for (var s in services) {
        for (var c in s.characteristics) {
          // Send ON command to activate sensor measurements on ESP32
          if (c.properties.write || c.properties.writeWithoutResponse) {
            final uuidLower = c.uuid.toString().toLowerCase();
            final sUuidLower = s.uuid.toString().toLowerCase();
            if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
              try {
                await c.write(utf8.encode('ON'), withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
              } catch (_) {}
            }
          }
          if (c.properties.notify || c.properties.indicate) {
            await c.setNotifyValue(true);
            final sub = c.onValueReceived.listen((bytes) {
              if (!mounted || !_measurementsEnabled) return;
              final str = String.fromCharCodes(bytes);
              setState(() {
                if (!_sensorData.parseFromRaw(str)) {
                  _sensorData.parseFromBatteryLevelBytes(bytes);
                }
              });
            });
            _bleSubscriptions.add(sub);
          } else if (c.properties.read) {
            // Read initial value
            try {
              final bytes = await c.read();
              final str = String.fromCharCodes(bytes);
              if (!_sensorData.parseFromRaw(str)) {
                _sensorData.parseFromBatteryLevelBytes(bytes);
              }
            } catch (_) {}
          }
        }
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Auto-subscribe error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.displayName ?? 'ESP32 Sensor Visualisations';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              widget.isStandaloneDemo
                  ? 'Visualisation Preview / Demo'
                  : 'Live Telemetry Dashboard',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: 'Sensor Calibration Options',
            onPressed: () => showSensorCalibrationDialog(
              context,
              sensorData: _sensorData,
              onSave: _saveCalibration,
              onCalibrateDry: _calibrateDry,
              onCalibrateWet: _calibrateWet,
              onReset: _resetCalibration,
            ),
          ),
          IconButton(
            icon: Icon(_measurementsEnabled ? Icons.pause_circle_outline : Icons.play_circle_outline),
            tooltip: _measurementsEnabled ? 'Pause Measurements' : 'Resume Measurements',
            onPressed: () => _toggleMeasurements(!_measurementsEnabled),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_customize), text: 'Dashboard'),
            Tab(icon: Icon(Icons.battery_charging_full), text: 'Battery'),
            Tab(icon: Icon(Icons.water_drop), text: 'Soil Moisture'),
            Tab(icon: Icon(Icons.show_chart), text: 'Trends'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Telemetry Status & Measurement Switch Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
            child: Row(
              children: [
                Icon(
                  !_measurementsEnabled
                      ? Icons.sensors_off
                      : (_isSimulating
                          ? Icons.auto_mode
                          : (_isAutoSubscribed ? Icons.wifi_tethering : Icons.info_outline)),
                  size: 18,
                  color: !_measurementsEnabled
                      ? Colors.grey
                      : (_isSimulating ? Colors.orange : theme.colorScheme.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    !_measurementsEnabled
                        ? 'Measurements: PAUSED (OFF)'
                        : (_isSimulating
                            ? 'Demo Simulation Active'
                            : (_sensorData.batteryPercent != null || _sensorData.soilPercent != null
                                ? 'Telemetry updated: ${_formatTime(_sensorData.lastUpdated)}'
                                : 'Streaming sensor telemetry from BLE...')),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (_isSimulating && _measurementsEnabled)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'SIMULATED',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange),
                    ),
                  ),
                Switch(
                  value: _measurementsEnabled,
                  activeTrackColor: theme.colorScheme.primary,
                  onChanged: (val) => _toggleMeasurements(val),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 1. All-in-One Dashboard Overview
                _buildDashboardTab(context),
                // 2. Battery Focused Visualisations
                _buildBatteryTab(context),
                // 3. Soil Moisture Focused Visualisations
                _buildSoilTab(context),
                // 4. Live Sensor Trends Chart
                _buildTrendsTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Battery Card
        BatteryCellCard(
          percent: _sensorData.batteryPercent ?? 0.0,
          voltage: _sensorData.batteryVoltage,
        ),
        const SizedBox(height: 12),
        // Soil Moisture Card
        SoilPotCard(
          percent: _sensorData.soilPercent ?? 0.0,
          voltage: _sensorData.soilVoltage,
          raw: _sensorData.soilRaw,
        ),
        const SizedBox(height: 12),
        // Combined Live Trend Chart
        SensorTrendChart(
          data: _sensorData,
          title: 'Live Sensor Trends (Battery & Soil)',
        ),
        const SizedBox(height: 12),
        _buildInteractiveControlsCard(context),
      ],
    );
  }

  Widget _buildBatteryTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        BatteryVisualizer(
          data: _sensorData,
          initialStyle: BatteryVisualizerStyle.cell,
          showControls: true,
        ),
        const SizedBox(height: 12),
        SensorTrendChart(
          data: _sensorData,
          title: 'Battery Historical Curve',
          showBattery: true,
          showSoil: false,
        ),
      ],
    );
  }

  Widget _buildSoilTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SoilVisualizer(
          data: _sensorData,
          initialStyle: SoilVisualizerStyle.pot,
          showControls: true,
          onCalibrateCurrentDry: _calibrateDry,
          onCalibrateCurrentWet: _calibrateWet,
          onCalibrationSaved: _saveCalibration,
          onResetCalibration: _resetCalibration,
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                const Icon(Icons.tune, color: Colors.cyan, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Sensor Calibration',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Dry: ${_sensorData.dryVolt.toStringAsFixed(2)}V (0%) | Wet: ${_sensorData.wetVolt.toStringAsFixed(2)}V (100%)',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  onPressed: () => showSensorCalibrationDialog(
                    context,
                    sensorData: _sensorData,
                    onSave: _saveCalibration,
                    onCalibrateDry: _calibrateDry,
                    onCalibrateWet: _calibrateWet,
                    onReset: _resetCalibration,
                  ),
                  child: const Text('Calibrate'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SensorTrendChart(
          data: _sensorData,
          title: 'Soil Moisture Historical Trend',
          showBattery: false,
          showSoil: true,
        ),
      ],
    );
  }

  Widget _buildTrendsTab(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        SensorTrendChart(
          data: _sensorData,
          title: 'Combined Multi-Sensor Telemetry',
          showBattery: true,
          showSoil: true,
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Telemetry Statistics',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildStatRow('Battery (Latest)', '${_sensorData.batteryPercent?.toStringAsFixed(1) ?? '---'} % (${_sensorData.batteryVoltage?.toStringAsFixed(3) ?? '---'} V)'),
                const Divider(),
                _buildStatRow('Soil Moisture (Latest)', '${_sensorData.soilPercent?.toStringAsFixed(1) ?? '---'} % (${_sensorData.soilVoltage?.toStringAsFixed(2) ?? '---'} V)'),
                const Divider(),
                _buildStatRow('Total History Samples', '${_sensorData.history.length} / ${SensorData.maxHistoryLength}'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildInteractiveControlsCard(BuildContext context) {
    final theme = Theme.of(context);
    final batPct = _sensorData.batteryPercent ?? 50.0;
    final soilPct = _sensorData.soilPercent ?? 50.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.tune),
        title: const Text('Manual Sensor Test Sliders', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Adjust values manually to test visualisations', style: TextStyle(fontSize: 12)),
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Battery: ${batPct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${(3.0 + (batPct / 100.0) * 1.2).toStringAsFixed(2)} V', style: TextStyle(color: theme.colorScheme.outline)),
                  ],
                ),
                Slider(
                  value: batPct.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: Colors.green,
                  onChanged: (val) {
                    if (_isSimulating) _stopSimulation();
                    setState(() {
                      _sensorData.update(
                        newBatteryPercent: val,
                        newBatteryVoltage: 3.0 + (val / 100.0) * 1.2,
                      );
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Soil Moisture: ${soilPct.toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('${(1.78 - (soilPct / 100.0) * (1.78 - 0.95)).toStringAsFixed(2)} V', style: TextStyle(color: theme.colorScheme.outline)),
                  ],
                ),
                Slider(
                  value: soilPct.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  divisions: 100,
                  activeColor: Colors.cyan,
                  onChanged: (val) {
                    if (_isSimulating) _stopSimulation();
                    final volt = 1.78 - (val / 100.0) * (1.78 - 0.95);
                    setState(() {
                      _sensorData.update(
                        newSoilPercent: val,
                        newSoilVoltage: volt,
                        newSoilRaw: ((volt / 3.3) * 4095).toInt(),
                      );
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
