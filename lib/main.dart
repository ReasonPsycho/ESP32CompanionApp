import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'models/sensor_data.dart';
import 'widgets/battery_visualizer.dart';
import 'widgets/soil_visualizer.dart';
import 'widgets/sensor_chart.dart';
import 'screens/visualisations_screen.dart';

void main() {
  // Set FlutterBluePlus log level if needed
  FlutterBluePlus.setLogLevel(LogLevel.info, color: true);
  runApp(const Esp32BleApp());
}

class Esp32BleApp extends StatelessWidget {
  const Esp32BleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XIAO ESP32-C5 Controller',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00838F),
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00838F),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const BleScannerScreen(),
    );
  }
}

class BleScannerScreen extends StatefulWidget {
  const BleScannerScreen({super.key});

  @override
  State<BleScannerScreen> createState() => _BleScannerScreenState();
}

class _BleScannerScreenState extends State<BleScannerScreen> {
  BluetoothAdapterState _adapterState = BluetoothAdapterState.unknown;
  List<ScanResult> _scanResults = [];
  bool _isScanning = false;
  String _searchFilter = '';
  final TextEditingController _searchController = TextEditingController();

  late StreamSubscription<BluetoothAdapterState> _adapterStateSubscription;
  late StreamSubscription<List<ScanResult>> _scanResultsSubscription;
  late StreamSubscription<bool> _isScanningSubscription;

  @override
  void initState() {
    super.initState();

    _adapterStateSubscription = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() => _adapterState = state);
      }
    });

    _scanResultsSubscription = FlutterBluePlus.scanResults.listen((results) {
      if (mounted) {
        setState(() => _scanResults = results);
      }
    });

    _isScanningSubscription = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) {
        setState(() => _isScanning = scanning);
      }
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription.cancel();
    _scanResultsSubscription.cancel();
    _isScanningSubscription.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    try {
      if (_adapterState != BluetoothAdapterState.on) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Bluetooth before scanning'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting scan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    try {
      await FlutterBluePlus.stopScan();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping scan: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  bool _isEsp32Device(ScanResult result) {
    final name = (result.device.platformName.isNotEmpty
            ? result.device.platformName
            : result.advertisementData.advName)
        .toLowerCase();
    final hasSensorUuid = result.advertisementData.serviceUuids.any((uuid) {
      final s = uuid.str128.toLowerCase();
      return s.contains('4fafc201') || s.contains('180f');
    });
    return name.contains('xiao') ||
        name.contains('esp32') ||
        name.contains('c5') ||
        name.contains('seeed') ||
        name.contains('soil') ||
        hasSensorUuid;
  }

  List<ScanResult> get _filteredScanResults {
    var list = List<ScanResult>.from(_scanResults);
    if (_searchFilter.trim().isNotEmpty) {
      final q = _searchFilter.trim().toLowerCase();
      list = list.where((r) {
        final name = (r.device.platformName.isNotEmpty
                ? r.device.platformName
                : r.advertisementData.advName)
            .toLowerCase();
        final id = r.device.remoteId.str.toLowerCase();
        return name.contains(q) || id.contains(q);
      }).toList();
    }

    // Sort: devices with names first, ESP32 matches prioritized, then by RSSI
    list.sort((a, b) {
      final aIsEsp = _isEsp32Device(a);
      final bIsEsp = _isEsp32Device(b);
      if (aIsEsp && !bIsEsp) return -1;
      if (!aIsEsp && bIsEsp) return 1;

      final aName = a.device.platformName.isNotEmpty
          ? a.device.platformName
          : a.advertisementData.advName;
      final bName = b.device.platformName.isNotEmpty
          ? b.device.platformName
          : b.advertisementData.advName;
      if (aName.isNotEmpty && bName.isEmpty) return -1;
      if (aName.isEmpty && bName.isNotEmpty) return 1;

      return b.rssi.compareTo(a.rssi);
    });

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBtOn = _adapterState == BluetoothAdapterState.on;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.bluetooth_audio, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'XIAO ESP32-C5 BLE',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    isBtOn
                        ? (_isScanning ? 'Scanning for devices...' : 'Bluetooth Ready')
                        : 'Bluetooth: ${_adapterState.name}',
                    style: TextStyle(
                      fontSize: 12,
                      color: isBtOn
                          ? (_isScanning ? Colors.greenAccent : Colors.white70)
                          : Colors.orangeAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Visualisations Demo',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const VisualisationsScreen(
                    isStandaloneDemo: true,
                    displayName: 'XIAO ESP32 Visualisations Demo',
                  ),
                ),
              );
            },
          ),
          if (_isScanning)
            IconButton(
              icon: const Icon(Icons.stop),
              tooltip: 'Stop Scan',
              onPressed: _stopScan,
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Start Scan',
              onPressed: isBtOn ? _startScan : null,
            ),
        ],
      ),
      body: Column(
        children: [
          if (!isBtOn)
            Container(
              color: Colors.amber.shade800,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Bluetooth is ${_adapterState.name}. Please turn on Bluetooth.',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      try {
                        await FlutterBluePlus.turnOn();
                      } catch (_) {}
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child: const Text('Turn ON'),
                  ),
                ],
              ),
            ),
          if (_isScanning) const LinearProgressIndicator(),
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Filter by device name or MAC address...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchFilter.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchFilter = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (val) {
                setState(() => _searchFilter = val);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              children: [
                Text(
                  'Found ${_filteredScanResults.length} device${_filteredScanResults.length == 1 ? '' : 's'}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.outline,
                  ),
                ),
                const Spacer(),
                ActionChip(
                  avatar: const Icon(Icons.memory, size: 16),
                  label: const Text('XIAO / ESP32'),
                  onPressed: () {
                    _searchController.text = 'xiao';
                    setState(() => _searchFilter = 'xiao');
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: _filteredScanResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isScanning ? Icons.bluetooth_searching : Icons.devices_other,
                          size: 64,
                          color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _isScanning
                              ? 'Searching for nearby BLE devices...'
                              : 'No devices found.\nTap the button below to scan.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: theme.colorScheme.outline,
                            fontSize: 16,
                          ),
                        ),
                        if (!_isScanning && isBtOn) ...[
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _startScan,
                            icon: const Icon(Icons.search),
                            label: const Text('Scan for XIAO ESP32-C5'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _filteredScanResults.length,
                    itemBuilder: (context, index) {
                      final result = _filteredScanResults[index];
                      final isEsp = _isEsp32Device(result);
                      final deviceName = result.device.platformName.isNotEmpty
                          ? result.device.platformName
                          : (result.advertisementData.advName.isNotEmpty
                              ? result.advertisementData.advName
                              : 'Unknown Device');

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: isEsp
                              ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
                              : BorderSide.none,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isEsp
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.surfaceContainerHighest,
                            child: Icon(
                              isEsp ? Icons.memory : Icons.bluetooth,
                              color: isEsp
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  deviceName,
                                  style: TextStyle(
                                    fontWeight: isEsp ? FontWeight.bold : FontWeight.w500,
                                  ),
                                ),
                              ),
                              if (isEsp)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'ESP32',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                result.device.remoteId.str,
                                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    Icons.signal_cellular_alt,
                                    size: 14,
                                    color: _getRssiColor(result.rssi),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${result.rssi} dBm',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _getRssiColor(result.rssi),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (result.advertisementData.connectable) ...[
                                    const SizedBox(width: 8),
                                    const Text('• Connectable',
                                        style: TextStyle(fontSize: 12, color: Colors.green)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                          trailing: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isEsp
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.secondaryContainer,
                              foregroundColor: isEsp
                                  ? theme.colorScheme.onPrimary
                                  : theme.colorScheme.onSecondaryContainer,
                            ),
                            onPressed: () => _navigateToDevice(result.device, deviceName),
                            child: const Text('Connect'),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isBtOn ? (_isScanning ? _stopScan : _startScan) : null,
        icon: Icon(_isScanning ? Icons.stop : Icons.search),
        label: Text(_isScanning ? 'Stop Scan' : 'Scan BLE'),
      ),
    );
  }

  Color _getRssiColor(int rssi) {
    if (rssi >= -60) return Colors.green;
    if (rssi >= -75) return Colors.lightGreen;
    if (rssi >= -85) return Colors.orange;
    return Colors.red;
  }

  void _navigateToDevice(BluetoothDevice device, String displayName) {
    _stopScan();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => DeviceDetailScreen(
          device: device,
          displayName: displayName,
        ),
      ),
    );
  }
}

class DeviceDetailScreen extends StatefulWidget {
  final BluetoothDevice device;
  final String displayName;

  const DeviceDetailScreen({
    super.key,
    required this.device,
    required this.displayName,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  BluetoothConnectionState _connectionState = BluetoothConnectionState.disconnected;
  List<BluetoothService> _services = [];
  bool _isConnecting = false;
  bool _isDiscovering = false;
  bool _measurementsEnabled = true; // Auto-measure enabled by default
  int? _mtu;
  final Map<String, String> _lastReadValues = {};
  final Map<String, StreamSubscription<List<int>>> _notificationSubscriptions = {};
  final List<String> _consoleLogs = [];
  final SensorData _sensorData = SensorData();

  late StreamSubscription<BluetoothConnectionState> _connectionStateSubscription;
  late StreamSubscription<int> _mtuSubscription;

  @override
  void initState() {
    super.initState();

    _connectionStateSubscription = widget.device.connectionState.listen((state) {
      if (mounted) {
        setState(() => _connectionState = state);
        if (state == BluetoothConnectionState.connected) {
          _log('Connected to ${widget.displayName}');
          _discoverServices();
        } else if (state == BluetoothConnectionState.disconnected) {
          _log('Disconnected from ${widget.displayName}');
        }
      }
    });

    _mtuSubscription = widget.device.mtu.listen((mtu) {
      if (mounted) {
        setState(() => _mtu = mtu);
      }
    });

    _connect();
  }

  @override
  void dispose() {
    for (var sub in _notificationSubscriptions.values) {
      sub.cancel();
    }
    _connectionStateSubscription.cancel();
    _mtuSubscription.cancel();
    super.dispose();
  }

  void _log(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    setState(() {
      _consoleLogs.insert(0, '[$timestamp] $message');
      if (_consoleLogs.length > 100) {
        _consoleLogs.removeLast();
      }
    });
  }

  Future<void> _connect() async {
    setState(() => _isConnecting = true);
    _log('Connecting to ${widget.device.remoteId.str}...');
    try {
      await widget.device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 15),
        autoConnect: false,
      );
    } catch (e) {
      _log('Connection error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  Future<void> _disconnect() async {
    _log('Disconnecting...');
    try {
      await widget.device.disconnect();
    } catch (e) {
      _log('Disconnect error: $e');
    }
  }

  Future<void> _discoverServices() async {
    setState(() => _isDiscovering = true);
    _log('Discovering GATT services...');
    try {
      final services = await widget.device.discoverServices();
      if (mounted) {
        setState(() => _services = services);
        _log('Found ${services.length} services.');
        if (_measurementsEnabled) {
          // Assume we do measurements always when connected
          _startMeasurements();
        }
      }
    } catch (e) {
      _log('Error discovering services: $e');
    } finally {
      if (mounted) {
        setState(() => _isDiscovering = false);
      }
    }
  }

  void _processIncomingTelemetry(List<int> bytes) {
    if (bytes.isEmpty || !_measurementsEnabled) return;
    try {
      final str = utf8.decode(bytes);
      if (!_sensorData.parseFromRaw(str)) {
        _sensorData.parseFromBatteryLevelBytes(bytes);
      }
    } catch (_) {
      _sensorData.parseFromBatteryLevelBytes(bytes);
    }
  }

  Future<void> _setMeasurementsEnabled(bool enabled) async {
    setState(() => _measurementsEnabled = enabled);
    if (enabled) {
      _log('Switching measurements ON...');
      await _startMeasurements();
    } else {
      _log('Switching measurements OFF...');
      await _stopMeasurements();
    }
  }

  Future<void> _startMeasurements() async {
    _log('Starting sensor telemetry streams...');
    int count = 0;
    for (var service in _services) {
      for (var c in service.characteristics) {
        // Send ON command to writable sensor control characteristic if present
        if (c.properties.write || c.properties.writeWithoutResponse) {
          final uuidLower = c.uuid.toString().toLowerCase();
          final sUuidLower = service.uuid.toString().toLowerCase();
          if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
            try {
              await c.write(utf8.encode('ON'), withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
            } catch (_) {}
          }
        }
        if (c.properties.notify || c.properties.indicate) {
          final uuidStr = c.uuid.toString();
          if (!_notificationSubscriptions.containsKey(uuidStr)) {
            await _subscribeCharacteristic(c);
            count++;
          }
        }
        if (c.properties.read) {
          try {
            await _readCharacteristic(c);
          } catch (_) {}
        }
      }
    }
    _log('Measurements active ($count sensor streams running)');
  }

  Future<void> _stopMeasurements() async {
    _log('Stopping sensor telemetry streams...');
    for (var service in _services) {
      for (var c in service.characteristics) {
        // Send OFF command to writable sensor control characteristic if present
        if (c.properties.write || c.properties.writeWithoutResponse) {
          final uuidLower = c.uuid.toString().toLowerCase();
          final sUuidLower = service.uuid.toString().toLowerCase();
          if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
            try {
              await c.write(utf8.encode('OFF'), withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
            } catch (_) {}
          }
        }
        final uuidStr = c.uuid.toString();
        if (_notificationSubscriptions.containsKey(uuidStr)) {
          try {
            await c.setNotifyValue(false);
          } catch (_) {}
          await _notificationSubscriptions[uuidStr]?.cancel();
          _notificationSubscriptions.remove(uuidStr);
        }
      }
    }
    if (mounted) {
      setState(() {});
    }
    _log('Measurements paused (all sensor streams stopped)');
  }

  Future<void> _subscribeCharacteristic(BluetoothCharacteristic c) async {
    final uuidStr = c.uuid.toString();
    try {
      await c.setNotifyValue(true);
      final sub = c.onValueReceived.listen((value) {
        if (!_measurementsEnabled) return;
        final str = _formatBytes(value);
        _processIncomingTelemetry(value);
        if (mounted) {
          setState(() {
            _lastReadValues[uuidStr] = str;
          });
          _log('Notify [${c.uuid}]: $str');
        }
      });
      _notificationSubscriptions[uuidStr] = sub;
      if (mounted) setState(() {});
    } catch (e) {
      _log('Subscribe error [$uuidStr]: $e');
    }
  }

  Future<void> _readCharacteristic(BluetoothCharacteristic c) async {
    try {
      _log('Reading ${c.uuid}...');
      final value = await c.read();
      final str = _formatBytes(value);
      _processIncomingTelemetry(value);
      setState(() {
        _lastReadValues[c.uuid.toString()] = str;
      });
      _log('Read [${c.uuid}]: $str');
    } catch (e) {
      _log('Read error [${c.uuid}]: $e');
    }
  }

  Future<void> _writeCharacteristic(BluetoothCharacteristic c, String text) async {
    try {
      _log('Writing "$text" to ${c.uuid}...');
      final bytes = utf8.encode(text);
      await c.write(bytes, withoutResponse: c.properties.writeWithoutResponse && !c.properties.write);
      _log('Write success [${c.uuid}]');
      // Update read value display if applicable
      setState(() {
        _lastReadValues[c.uuid.toString()] = text;
      });
    } catch (e) {
      _log('Write error [${c.uuid}]: $e');
    }
  }

  Future<void> _toggleNotify(BluetoothCharacteristic c) async {
    final uuidStr = c.uuid.toString();
    final isSubscribed = _notificationSubscriptions.containsKey(uuidStr);

    try {
      if (isSubscribed) {
        _log('Disabling notify for $uuidStr');
        await c.setNotifyValue(false);
        await _notificationSubscriptions[uuidStr]?.cancel();
        _notificationSubscriptions.remove(uuidStr);
        setState(() {});
      } else {
        _log('Enabling notify for $uuidStr');
        await c.setNotifyValue(true);
        final sub = c.onValueReceived.listen((value) {
          final str = _formatBytes(value);
          _processIncomingTelemetry(value);
          if (mounted) {
            setState(() {
              _lastReadValues[uuidStr] = str;
            });
            _log('Notify [${c.uuid}]: $str');
          }
        });
        _notificationSubscriptions[uuidStr] = sub;
        setState(() {});
      }
    } catch (e) {
      _log('Notify toggle error [$uuidStr]: $e');
    }
  }

  String _formatBytes(List<int> bytes) {
    if (bytes.isEmpty) return '(empty)';
    try {
      final utf8Str = utf8.decode(bytes);
      // Check if printable
      if (utf8Str.runes.every((r) => (r >= 32 && r <= 126) || r == 10 || r == 13 || r == 9)) {
        return utf8Str;
      }
    } catch (_) {}
    return 'Hex: [${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ')}]';
  }

  void _showWriteDialog(BluetoothCharacteristic c) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Data to ESP32'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Characteristic: ${c.uuid}',
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Data / Command (UTF-8 text)',
                hintText: 'e.g. LED_ON, HELLO, 123',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              if (controller.text.isNotEmpty) {
                _writeCharacteristic(c, controller.text);
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isConnected = _connectionState == BluetoothConnectionState.connected;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.displayName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                widget.device.remoteId.str,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            if (isConnected)
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
            if (isConnected)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Rediscover Services',
                onPressed: _discoverServices,
              ),
            if (isConnected)
              IconButton(
                icon: const Icon(Icons.link_off),
                tooltip: 'Disconnect',
                onPressed: _disconnect,
              )
            else
              IconButton(
                icon: const Icon(Icons.link),
                tooltip: 'Connect',
                onPressed: _isConnecting ? null : _connect,
              ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.analytics_outlined), text: 'Visualisations'),
              Tab(icon: Icon(Icons.hub_outlined), text: 'Services & GATT'),
              Tab(icon: Icon(Icons.terminal), text: 'Console Log'),
            ],
          ),
        ),
        body: Column(
          children: [
            // Connection Status Banner
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: isConnected
                  ? Colors.green.shade800
                  : (_isConnecting ? Colors.orange.shade800 : Colors.red.shade800),
              child: Row(
                children: [
                  Icon(
                    isConnected
                        ? Icons.check_circle_outline
                        : (_isConnecting ? Icons.sync : Icons.error_outline),
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isConnecting
                        ? 'Connecting...'
                        : 'Status: ${_connectionState.name.toUpperCase()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  if (_mtu != null && isConnected)
                    Text(
                      'MTU: $_mtu',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            if (_isDiscovering) const LinearProgressIndicator(),
            Expanded(
              child: TabBarView(
                children: [
                  // Visualisations Tab
                  _buildVisualisationsTab(theme, isConnected),
                  // Services & Characteristics Tab
                  _buildServicesTab(theme, isConnected),
                  // Console Log Tab
                  _buildConsoleTab(theme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendBleCalibrationCommand(String cmd) async {
    for (var service in _services) {
      for (var c in service.characteristics) {
        if (c.properties.write || c.properties.writeWithoutResponse) {
          final uuidLower = c.uuid.toString().toLowerCase();
          final sUuidLower = service.uuid.toString().toLowerCase();
          if (uuidLower.contains('beb5483e') || sUuidLower.contains('4fafc201')) {
            await _writeCharacteristic(c, cmd);
            return;
          }
        }
      }
    }
  }

  void _calibrateDry() {
    setState(() {
      _sensorData.calibrateDry();
    });
    _sendBleCalibrationCommand('CAL_DRY');
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
    _sendBleCalibrationCommand('CAL_WET');
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
    _sendBleCalibrationCommand('CAL:${dry.toStringAsFixed(2)},${wet.toStringAsFixed(2)}');
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
    _sendBleCalibrationCommand('CAL_RESET');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sensor calibration reset to factory defaults (1.78V / 0.95V)'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildVisualisationsTab(ThemeData theme, bool isConnected) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (!isConnected)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.orange.shade800,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Device is disconnected. Connect to receive live BLE data, or use test sliders below.',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildMeasurementSwitchCard(theme),
          ),
        // Battery Visualisation Switcher
        BatteryVisualizer(
          data: _sensorData,
          initialStyle: BatteryVisualizerStyle.cell,
          showControls: true,
        ),
        const SizedBox(height: 12),
        // Soil Moisture / Capacitive Sensor Switcher
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
        // Live Trends Chart
        SensorTrendChart(
          data: _sensorData,
          title: 'Live Sensor Telemetry Trends',
        ),
        const SizedBox(height: 12),
        _buildManualSlidersCard(theme),
      ],
    );
  }

  Widget _buildMeasurementSwitchCard(ThemeData theme) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: _measurementsEnabled
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _measurementsEnabled
                    ? Colors.green.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _measurementsEnabled ? Icons.sensors : Icons.sensors_off,
                color: _measurementsEnabled ? Colors.green : Colors.grey,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        'Live Measurements',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _measurementsEnabled
                              ? Colors.green.shade800
                              : Colors.grey.shade700,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _measurementsEnabled ? 'ACTIVE (ON)' : 'PAUSED (OFF)',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _measurementsEnabled
                        ? 'Actively streaming battery and soil sensor readings'
                        : 'Measurements paused to conserve battery & sensor life',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Switch(
              value: _measurementsEnabled,
              activeTrackColor: theme.colorScheme.primary,
              onChanged: (val) => _setMeasurementsEnabled(val),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualSlidersCard(ThemeData theme) {
    final batPct = _sensorData.batteryPercent ?? 50.0;
    final soilPct = _sensorData.soilPercent ?? 50.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.tune),
        title: const Text('Visualisation Test Sliders', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Simulate battery and soil capacitive readings', style: TextStyle(fontSize: 12)),
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

  Widget _buildServicesTab(ThemeData theme, bool isConnected) {
    if (!isConnected) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth_disabled, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'Device is not connected',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _isConnecting ? null : _connect,
              icon: const Icon(Icons.link),
              label: Text(_isConnecting ? 'Connecting...' : 'Reconnect'),
            ),
          ],
        ),
      );
    }

    if (_services.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isDiscovering) ...[
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Discovering GATT Services...'),
            ] else ...[
              const Icon(Icons.info_outline, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              const Text('No GATT services discovered yet.'),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _discoverServices,
                icon: const Icon(Icons.search),
                label: const Text('Discover Services'),
              ),
            ],
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: _services.length,
      itemBuilder: (context, index) {
        final service = _services[index];
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          elevation: 2,
          child: ExpansionTile(
            initiallyExpanded: true,
            leading: Icon(
              service.isPrimary ? Icons.folder_special : Icons.folder,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              'Service: ${_getServiceName(service.uuid)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            subtitle: Text(
              service.uuid.toString(),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
            children: service.characteristics.map((c) {
              final uuidStr = c.uuid.toString();
              final isNotifying = _notificationSubscriptions.containsKey(uuidStr);
              final lastValue = _lastReadValues[uuidStr];

              return Container(
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.3)),
                  ),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: theme.colorScheme.secondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Characteristic: ${_getCharName(c.uuid)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      uuidStr,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Characteristic Properties Chips & Actions
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (c.properties.read)
                          ActionChip(
                            avatar: const Icon(Icons.download, size: 14),
                            label: const Text('Read'),
                            onPressed: () => _readCharacteristic(c),
                          ),
                        if (c.properties.write || c.properties.writeWithoutResponse)
                          ActionChip(
                            avatar: const Icon(Icons.upload, size: 14),
                            label: const Text('Write'),
                            onPressed: () => _showWriteDialog(c),
                          ),
                        if (c.properties.notify || c.properties.indicate)
                          FilterChip(
                            avatar: Icon(
                              isNotifying ? Icons.notifications_active : Icons.notifications_none,
                              size: 14,
                            ),
                            label: Text(isNotifying ? 'Subscribed' : 'Notify'),
                            selected: isNotifying,
                            onSelected: (_) => _toggleNotify(c),
                          ),
                      ],
                    ),
                    if (lastValue != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'Value: $lastValue',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildConsoleTab(ThemeData theme) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Logs (${_consoleLogs.length})',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              TextButton.icon(
                icon: const Icon(Icons.clear_all, size: 18),
                label: const Text('Clear'),
                onPressed: () {
                  setState(() => _consoleLogs.clear());
                },
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _consoleLogs.isEmpty
              ? const Center(
                  child: Text(
                    'No logs yet.',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.builder(
                  reverse: false,
                  itemCount: _consoleLogs.length,
                  itemBuilder: (context, index) {
                    final log = _consoleLogs[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      child: Text(
                        log,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _getServiceName(Guid uuid) {
    final str = uuid.toString().toUpperCase();
    if (str.startsWith('00001800')) return 'Generic Access (0x1800)';
    if (str.startsWith('00001801')) return 'Generic Attribute (0x1801)';
    if (str.startsWith('0000180A')) return 'Device Information (0x180A)';
    if (str.startsWith('0000180F')) return 'Battery Service (0x180F)';
    if (str.startsWith('0000FFE0') || str.startsWith('0000FFF0')) return 'ESP32 Custom UART Service';
    return uuid.toString();
  }

  String _getCharName(Guid uuid) {
    final str = uuid.toString().toUpperCase();
    if (str.startsWith('00002A00')) return 'Device Name (0x2A00)';
    if (str.startsWith('00002A01')) return 'Appearance (0x2A01)';
    if (str.startsWith('00002A19')) return 'Battery Level (0x2A19)';
    if (str.startsWith('00002A29')) return 'Manufacturer Name (0x2A29)';
    if (str.startsWith('0000FFE1') || str.startsWith('0000FFF1')) return 'ESP32 Data TX/RX';
    return uuid.toString();
  }
}
