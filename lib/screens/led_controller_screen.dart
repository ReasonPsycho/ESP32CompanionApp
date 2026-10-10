import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/led_matrix_data.dart';
import '../widgets/led_matrix_display.dart';
import '../widgets/gamepad_controller.dart';

class LedControllerScreen extends StatefulWidget {
  final BluetoothDevice? device;
  final String? displayName;
  final LedMatrixData? initialData;
  final bool isStandaloneDemo;

  const LedControllerScreen({
    super.key,
    this.device,
    this.displayName,
    this.initialData,
    this.isStandaloneDemo = false,
  });

  @override
  State<LedControllerScreen> createState() => _LedControllerScreenState();
}

class _LedControllerScreenState extends State<LedControllerScreen> {
  late LedMatrixData _data;
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  bool _isConnecting = false;
  bool _isSubscribed = false;
  Color _selectedDrawColor = const Color(0xFF00FF88);

  Timer? _simulationTimer;
  double _simStep = 0.0;
  final List<StreamSubscription> _bleSubscriptions = [];

  BluetoothCharacteristic? _commandChar;
  BluetoothCharacteristic? _matrixChar;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData ??
        (widget.isStandaloneDemo ? LedMatrixData.sample() : LedMatrixData());

    if (widget.device != null) {
      _initBleConnection();
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
    super.dispose();
  }

  void _startSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted) return;
      _simStep += 0.5;
      setState(() {
        _data.simulateStep(_simStep);
      });
    });
  }

  Future<void> _initBleConnection() async {
    if (widget.device == null) return;

    final connSub = widget.device!.connectionState.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
        if (state == BluetoothConnectionState.connected && !_isSubscribed) {
          _discoverAndSubscribe();
        }
      }
    });
    _bleSubscriptions.add(connSub);

    try {
      final current = await widget.device!.connectionState.first;
      if (current != BluetoothConnectionState.connected) {
        setState(() => _isConnecting = true);
        await widget.device!.connect(
          license: License.nonprofit,
          timeout: const Duration(seconds: 15),
          autoConnect: false,
        );
      } else {
        _discoverAndSubscribe();
      }
    } catch (_) {
      // Connect timeout / error
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _discoverAndSubscribe() async {
    if (widget.device == null) return;
    try {
      final services = await widget.device!.discoverServices();
      for (var s in services) {
        for (var c in s.characteristics) {
          final uStr = c.uuid.toString().toLowerCase();

          // Command characteristic (Dedicated or Generic)
          if (uStr.contains('8411e2dc-0002') ||
              uStr.contains('beb5483e') ||
              c.properties.write ||
              c.properties.writeWithoutResponse) {
            _commandChar = c;
          }

          // Status telemetry notification
          if ((uStr.contains('8411e2dc-0003') || uStr.contains('beb5483e')) &&
              (c.properties.notify || c.properties.indicate)) {
            await c.setNotifyValue(true);
            final sub = c.onValueReceived.listen((value) {
              if (value.isNotEmpty) {
                try {
                  final str = utf8.decode(value);
                  if (_data.parseFromStatusJson(str) && mounted) {
                    setState(() {});
                  }
                } catch (_) {}
              }
            });
            _bleSubscriptions.add(sub);
          }

          // Matrix frame telemetry & command characteristic
          if (uStr.contains('8411e2dc-0004')) {
            _matrixChar = c;
            if (c.properties.notify || c.properties.indicate) {
              await c.setNotifyValue(true);
              final sub = c.onValueReceived.listen((value) {
                if (value.isNotEmpty && mounted) {
                  if (_data.parseFromMatrixFrameBytes(value)) {
                    setState(() {});
                  }
                }
              });
              _bleSubscriptions.add(sub);
            }
          }

          // Standard Battery Service level
          if (uStr.contains('2a19') && (c.properties.notify || c.properties.indicate || c.properties.read)) {
            if (c.properties.notify) {
              await c.setNotifyValue(true);
              final sub = c.onValueReceived.listen((value) {
                if (value.isNotEmpty && mounted) {
                  setState(() => _data.batteryPercent = value[0]);
                }
              });
              _bleSubscriptions.add(sub);
            }
            if (c.properties.read) {
              try {
                final val = await c.read();
                if (val.isNotEmpty && mounted) {
                  setState(() => _data.batteryPercent = val[0]);
                }
              } catch (_) {}
            }
          }
        }
      }
      _isSubscribed = true;
    } catch (_) {}
  }

  Future<void> _sendCommand(String cmd) async {
    // If running in demo mode or simulating
    if (widget.isStandaloneDemo || widget.device == null) {
      _applyLocalSimulatedCommand(cmd);
      return;
    }

    if (_commandChar != null) {
      try {
        final bytes = utf8.encode(cmd);
        await _commandChar!.write(
          bytes,
          withoutResponse: _commandChar!.properties.writeWithoutResponse,
        );
      } catch (_) {}
    } else {
      // Try searching writable characteristic on the fly
      try {
        final services = await widget.device!.discoverServices();
        for (var s in services) {
          for (var c in s.characteristics) {
            if (c.properties.write || c.properties.writeWithoutResponse) {
              _commandChar = c;
              await c.write(utf8.encode(cmd), withoutResponse: c.properties.writeWithoutResponse);
              return;
            }
          }
        }
      } catch (_) {}
    }

    _applyLocalSimulatedCommand(cmd);
  }

  Future<void> _sendMatrixBoard() async {
    if (widget.isStandaloneDemo || widget.device == null) {
      setState(() {
        _data.activeGame = LedGameMode.customDraw.id;
        _data.estimatedCurrentMa = _data.computeEstimatedCurrentMa();
        _data.isPowerLimited = _data.estimatedCurrentMa >= _data.maxCurrentMa;
      });
      return;
    }

    if (_matrixChar != null && (_matrixChar!.properties.write || _matrixChar!.properties.writeWithoutResponse)) {
      try {
        final frameBytes = _data.toMatrixFrameBytes();
        await _matrixChar!.write(frameBytes, withoutResponse: _matrixChar!.properties.writeWithoutResponse);
      } catch (_) {}
    } else {
      // Fallback to sending hex board frame command
      final hex = _data.toMatrixFrameHex();
      await _sendCommand('FRAME:$hex');
    }

    setState(() {
      _data.activeGame = LedGameMode.customDraw.id;
      _data.estimatedCurrentMa = _data.computeEstimatedCurrentMa();
      _data.isPowerLimited = _data.estimatedCurrentMa >= _data.maxCurrentMa;
    });
  }

  void _applyLocalSimulatedCommand(String cmd) {
    setState(() {
      final upper = cmd.toUpperCase().trim();
      if (upper.startsWith('GAME:') || upper.startsWith('MODE:')) {
        final colon = cmd.indexOf(':');
        final arg = cmd.substring(colon + 1).trim();
        final int? id = int.tryParse(arg);
        if (id != null) {
          _data.activeGame = id;
          _data.isAuto = true;
        }
      } else if (upper.startsWith('SPEED:')) {
        final v = int.tryParse(cmd.substring(6).trim());
        if (v != null) _data.speedMs = v;
      } else if (upper.startsWith('BRIGHT:') || upper.startsWith('BRIGHTNESS:')) {
        final colon = cmd.indexOf(':');
        final v = int.tryParse(cmd.substring(colon + 1).trim());
        if (v != null) _data.brightness = v;
      } else if (upper.startsWith('LIMIT:') || upper.startsWith('MAX_CURRENT:') || upper.startsWith('CURRENT_LIMIT:')) {
        final colon = cmd.indexOf(':');
        final v = int.tryParse(cmd.substring(colon + 1).trim());
        if (v != null) _data.maxCurrentMa = v.clamp(50, LedMatrixData.hardPowerLimitMa);
      } else if (upper == 'ON' || upper == 'START') {
        _data.isRunning = true;
      } else if (upper == 'OFF' || upper == 'STOP') {
        _data.isRunning = false;
      } else if (upper == 'CLEAR') {
        _data.pixels = List.generate(LedMatrixData.numLeds, (_) => Colors.black);
      } else if (upper == 'RESET') {
        _data.score = 0;
        _data.lines = 0;
      } else if (upper.startsWith('FILL:')) {
        final colon = cmd.indexOf(':');
        final parts = cmd.substring(colon + 1).split(',');
        if (parts.length >= 3) {
          final r = int.tryParse(parts[0]) ?? 0;
          final g = int.tryParse(parts[1]) ?? 0;
          final b = int.tryParse(parts[2]) ?? 0;
          final fillCol = Color.fromARGB(255, r, g, b);
          _data.pixels = List.generate(LedMatrixData.numLeds, (_) => fillCol);
        }
      }
      _data.estimatedCurrentMa = _data.computeEstimatedCurrentMa();
      _data.isPowerLimited = _data.estimatedCurrentMa >= _data.maxCurrentMa;
    });
  }

  void _onPixelDrawn(int x, int y, Color color) {
    final idx = LedMatrixData.xyToIndex(x, y);
    setState(() {
      _data.activeGame = LedGameMode.customDraw.id;
      _data.pixels[idx] = color;
      _data.estimatedCurrentMa = _data.computeEstimatedCurrentMa();
      _data.isPowerLimited = _data.estimatedCurrentMa >= _data.maxCurrentMa;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isConnected = _connectionState == BluetoothConnectionState.connected;
    final isDemo = widget.isStandaloneDemo || widget.device == null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.displayName ?? (isDemo ? 'LED Matrix Simulator Demo' : 'ESP32 LED Matrix'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Row(
              children: [
                Icon(
                  isDemo
                      ? Icons.science_outlined
                      : (isConnected
                          ? Icons.bluetooth_connected
                          : (_isConnecting ? Icons.sync : Icons.bluetooth_disabled)),
                  size: 13,
                  color: isDemo || isConnected
                      ? Colors.greenAccent
                      : (_isConnecting ? Colors.orangeAccent : Colors.redAccent),
                ),
                const SizedBox(width: 4),
                Text(
                  isDemo
                      ? 'Interactive Simulation Mode'
                      : (isConnected
                          ? 'BLE Connected'
                          : (_isConnecting ? 'Connecting...' : 'BLE Disconnected')),
                  style: TextStyle(
                    fontSize: 11,
                    color: isDemo || isConnected
                        ? Colors.greenAccent
                        : (_isConnecting ? Colors.orangeAccent : Colors.redAccent),
                  ),
                ),
                if (!isDemo && isConnected) ...[
                  const SizedBox(width: 8),
                  const Text('•', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(width: 8),
                  Icon(
                    _data.batteryPercent > 20 ? Icons.battery_charging_full : Icons.battery_alert,
                    size: 13,
                    color: _data.batteryPercent > 20 ? Colors.greenAccent : Colors.redAccent,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${_data.batteryPercent}%',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ],
            ),
          ],
        ),
        actions: [
          if (!isDemo && isConnected)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Re-sync BLE',
              onPressed: _discoverAndSubscribe,
            ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              // 1. Live 8x8 LED Matrix Display
              Center(
                child: LedMatrixDisplay(
                  data: _data,
                  isInteractiveDraw: _data.mode == LedGameMode.customDraw,
                  selectedDrawColor: _selectedDrawColor,
                  onPixelDrawn: _onPixelDrawn,
                  size: 260.0,
                ),
              ),
              const SizedBox(height: 16),

              // 2. Gamepad & Mode Controls
              GamepadController(
                data: _data,
                onSendCommand: _sendCommand,
                onSendBoard: _sendMatrixBoard,
                currentDrawColor: _selectedDrawColor,
                onColorSelected: (col) => setState(() => _selectedDrawColor = col),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
