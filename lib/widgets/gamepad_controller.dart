import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/led_matrix_data.dart';

class GamepadController extends StatefulWidget {
  final LedMatrixData data;
  final Function(String command) onSendCommand;
  final VoidCallback? onSendBoard;
  final Function(Color color)? onColorSelected;
  final Color currentDrawColor;

  const GamepadController({
    super.key,
    required this.data,
    required this.onSendCommand,
    this.onSendBoard,
    this.onColorSelected,
    this.currentDrawColor = const Color(0xFF00FF00),
  });

  @override
  State<GamepadController> createState() => _GamepadControllerState();
}

class _GamepadControllerState extends State<GamepadController> {
  late int _tempBrightness;
  late int _tempSpeed;
  final TextEditingController _customCmdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tempBrightness = widget.data.brightness;
    _tempSpeed = widget.data.speedMs;
  }

  @override
  void didUpdateWidget(covariant GamepadController oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.brightness != widget.data.brightness) {
      _tempBrightness = widget.data.brightness;
    }
    if (oldWidget.data.speedMs != widget.data.speedMs) {
      _tempSpeed = widget.data.speedMs;
    }
  }

  @override
  void dispose() {
    _customCmdController.dispose();
    super.dispose();
  }

  void _triggerHaptic() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  void _sendCustomCommand(String cmd) {
    final trimmed = cmd.trim();
    if (trimmed.isEmpty) return;
    _triggerHaptic();
    widget.onSendCommand(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = widget.data.mode;

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Mode Selector Chips
          _buildModeSelector(context),
          const SizedBox(height: 16),

          // 2. Main Mode-Specific Controls Area
          if (mode == LedGameMode.tetris)
            _buildTetrisCard(context, theme)
          else if (mode == LedGameMode.gameOfLife)
            _buildLifeControls(context, theme)
          else if (mode == LedGameMode.customDraw)
            _buildDrawingTools(context, theme)
          else if (mode == LedGameMode.rainbow)
            _buildRainbowControls(context, theme),

          const SizedBox(height: 20),

          // 3. Global Speed & Brightness Controls
          _buildSlidersCard(context, theme),

          const SizedBox(height: 20),

          // 4. Custom Command Console Bar
          _buildCustomCommandCard(context, theme),
        ],
      ),
    );
  }

  Widget _buildModeSelector(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: LedGameMode.values.map((mode) {
          final isSelected = widget.data.activeGame == mode.id;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
              avatar: Icon(
                mode.icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.tealAccent,
              ),
              label: Text(mode.label),
              selected: isSelected,
              selectedColor: const Color(0xFF00838F),
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : null,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              onSelected: (val) {
                if (val) {
                  _triggerHaptic();
                  widget.onSendCommand('GAME:${mode.id}');
                }
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  // --- TETRIS AI CONTROLLER CARD ---
  Widget _buildTetrisCard(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Score & Status Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatPill('Score', '${widget.data.score}', Icons.stars, Colors.amber),
                _buildStatPill('Lines', '${widget.data.lines}', Icons.clear_all, Colors.cyan),
                _buildStatPill(
                  'Mode',
                  'AI Auto',
                  Icons.smart_toy,
                  Colors.purpleAccent,
                ),
              ],
            ),
            const Divider(height: 24),

            // AI Status info & action buttons
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined, color: Colors.purpleAccent, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Autonomous Tetris AI',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        'Autonomous engine actively computing optimum piece placement and clears.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand(widget.data.isRunning ? 'PAUSE' : 'RESUME');
                  },
                  icon: Icon(widget.data.isRunning ? Icons.pause : Icons.play_arrow),
                  label: Text(widget.data.isRunning ? 'Pause' : 'Resume'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.5)),
                  ),
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('RESET');
                  },
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset Board'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // --- CONWAY'S GAME OF LIFE CONTROLS ---
  Widget _buildLifeControls(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.grain, color: Color(0xFF00FF88)),
                SizedBox(width: 8),
                Text(
                  "Conway's Game of Life Engine",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Zero-player cellular automaton evolving by mathematical rule-sets on the 8x8 matrix.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 16),

            // Quick Preset / Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('STEP');
                  },
                  icon: const Icon(Icons.skip_next, size: 18),
                  label: const Text('Next Step'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('SEED');
                  },
                  icon: const Icon(Icons.shuffle, size: 18),
                  label: const Text('Random Seed'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('GLIDER');
                  },
                  icon: const Icon(Icons.send_outlined, size: 18),
                  label: const Text('Glider Preset'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('BLINKER');
                  },
                  icon: const Icon(Icons.repeat, size: 18),
                  label: const Text('Blinker Preset'),
                ),
                TextButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('CLEAR');
                  },
                  icon: const Icon(Icons.delete_sweep, size: 18, color: Colors.redAccent),
                  label: const Text('Clear Matrix', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- DRAWING CANVAS TOOLS ---
  Widget _buildDrawingTools(BuildContext context, ThemeData theme) {
    final List<Color> palette = [
      const Color(0xFFFF0000), // Red
      const Color(0xFF00FF00), // Green
      const Color(0xFF0000FF), // Blue
      const Color(0xFFFFFF00), // Yellow
      const Color(0xFF00FFFF), // Cyan
      const Color(0xFFFF00FF), // Magenta
      const Color(0xFFFF9900), // Orange
      const Color(0xFFFFFFFF), // White
      const Color(0xFF000000), // Black (Eraser)
    ];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette, color: Colors.tealAccent),
                SizedBox(width: 8),
                Text(
                  'Drawing Palette',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.tealAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 15, color: Colors.tealAccent),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Touch matrix to draw locally. Tap "Send to Matrix" to flash LEDs.',
                      style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Color Swatches
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: palette.map((col) {
                  final isSelected = col.toARGB32() == widget.currentDrawColor.toARGB32();
                  return GestureDetector(
                    onTap: () {
                      _triggerHaptic();
                      if (widget.onColorSelected != null) widget.onColorSelected!(col);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.white24,
                          width: isSelected ? 3.0 : 1.5,
                        ),
                        boxShadow: isSelected
                            ? [
                                BoxShadow(
                                  color: col.withValues(alpha: 0.6),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                      child: col.toARGB32() == 0xFF000000
                          ? const Icon(Icons.cleaning_services, size: 16, color: Colors.white70)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _triggerHaptic();
                    if (widget.onSendBoard != null) {
                      widget.onSendBoard!();
                    } else {
                      widget.onSendCommand('GET_BOARD');
                    }
                  },
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: const Text('Send to Matrix', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    final r = (widget.currentDrawColor.r * 255.0).round().clamp(0, 255);
                    final g = (widget.currentDrawColor.g * 255.0).round().clamp(0, 255);
                    final b = (widget.currentDrawColor.b * 255.0).round().clamp(0, 255);
                    widget.onSendCommand('FILL:$r,$g,$b');
                  },
                  icon: const Icon(Icons.format_color_fill),
                  label: const Text('Fill All'),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('CLEAR');
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                  label: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- RAINBOW WAVE EFFECT CONTROLS ---
  Widget _buildRainbowControls(BuildContext context, ThemeData theme) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.amber),
                SizedBox(width: 8),
                Text(
                  'Rainbow Wave Animation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Continuous smooth chromatic wave spectrum dynamically calculated on the ESP32 matrix.',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('SPEED:100');
                  },
                  icon: const Icon(Icons.speed),
                  label: const Text('Fast Wave (100ms)'),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    _triggerHaptic();
                    widget.onSendCommand('SPEED:400');
                  },
                  icon: const Icon(Icons.waves),
                  label: const Text('Smooth (400ms)'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // --- SLIDERS FOR SPEED & BRIGHTNESS ---
  Widget _buildSlidersCard(BuildContext context, ThemeData theme) {
    final bool hasPendingChanges =
        _tempBrightness != widget.data.brightness || _tempSpeed != widget.data.speedMs;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Brightness Slider Header
            Row(
              children: [
                const Icon(Icons.brightness_6, size: 20, color: Colors.amberAccent),
                const SizedBox(width: 8),
                Text(
                  'Brightness: ${((_tempBrightness / 255) * 100).round()}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text('$_tempBrightness / 255', style: const TextStyle(fontSize: 12, color: Colors.white60)),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.send, size: 18, color: Colors.amberAccent),
                  tooltip: 'Send Brightness Command',
                  onPressed: () => _sendCustomCommand('BRIGHT:$_tempBrightness'),
                ),
              ],
            ),
            Slider(
              value: _tempBrightness.toDouble().clamp(1.0, 255.0),
              min: 1.0,
              max: 255.0,
              activeColor: Colors.amberAccent,
              onChanged: (val) {
                setState(() => _tempBrightness = val.round());
              },
              onChangeEnd: (val) {
                _sendCustomCommand('BRIGHT:${val.round()}');
              },
            ),
            const SizedBox(height: 8),

            // Speed Slider Header
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 20, color: Colors.tealAccent),
                const SizedBox(width: 8),
                Text(
                  'Tick Speed: $_tempSpeed ms',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  _tempSpeed <= 200
                      ? 'Fast'
                      : _tempSpeed <= 500
                          ? 'Medium'
                          : 'Slow',
                  style: const TextStyle(fontSize: 12, color: Colors.tealAccent),
                ),
                const SizedBox(width: 6),
                IconButton(
                  icon: const Icon(Icons.send, size: 18, color: Colors.tealAccent),
                  tooltip: 'Send Speed Command',
                  onPressed: () => _sendCustomCommand('SPEED:$_tempSpeed'),
                ),
              ],
            ),
            Slider(
              value: _tempSpeed.toDouble().clamp(20.0, 1500.0),
              min: 20.0,
              max: 1500.0,
              divisions: 50,
              activeColor: Colors.tealAccent,
              onChanged: (val) {
                setState(() => _tempSpeed = val.round());
              },
              onChangeEnd: (val) {
                _sendCustomCommand('SPEED:${val.round()}');
              },
            ),

            if (hasPendingChanges) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent.withValues(alpha: 0.2),
                    foregroundColor: Colors.tealAccent,
                    side: BorderSide(color: Colors.tealAccent.withValues(alpha: 0.5)),
                  ),
                  onPressed: () {
                    _sendCustomCommand('BRIGHT:$_tempBrightness');
                    _sendCustomCommand('SPEED:$_tempSpeed');
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text('Apply & Send Settings'),
                ),
              ),
            ],

            // Pause / Resume Switch
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      widget.data.isRunning ? Icons.play_circle_fill : Icons.pause_circle_filled,
                      color: widget.data.isRunning ? Colors.greenAccent : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.data.isRunning ? 'Display Output Active' : 'Display Paused (LEDs Off)',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
                Switch(
                  value: widget.data.isRunning,
                  activeTrackColor: Colors.greenAccent,
                  onChanged: (val) {
                    _triggerHaptic();
                    widget.onSendCommand(val ? 'ON' : 'OFF');
                  },
                ),
              ],
            ),

            // 1.0A Power & Current Safety Monitor
            const Divider(),
            Row(
              children: [
                Icon(
                  Icons.electric_bolt,
                  size: 20,
                  color: widget.data.isPowerLimited ? Colors.amberAccent : Colors.lightGreenAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  'Current Draw: ${widget.data.estimatedCurrentMa} mA / ${widget.data.maxCurrentMa} mA',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.data.isPowerLimited
                        ? Colors.amber.withValues(alpha: 0.2)
                        : Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: widget.data.isPowerLimited ? Colors.amberAccent : Colors.greenAccent,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    widget.data.isPowerLimited ? 'LIMITING (1.0A)' : '1.0A Safe',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: widget.data.isPowerLimited ? Colors.amberAccent : Colors.greenAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (widget.data.estimatedCurrentMa / widget.data.maxCurrentMa).clamp(0.0, 1.0),
                minHeight: 8,
                backgroundColor: Colors.white12,
                valueColor: AlwaysStoppedAnimation<Color>(
                  widget.data.isPowerLimited
                      ? Colors.amberAccent
                      : widget.data.estimatedCurrentMa > 800
                          ? Colors.orangeAccent
                          : Colors.lightGreenAccent,
                ),
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Hardware protection ceiling strictly enforced at 1.0A (1000mA) via dynamic subpixel attenuation.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }

  // --- CUSTOM COMMAND INPUT CONSOLE CARD ---
  Widget _buildCustomCommandCard(BuildContext context, ThemeData theme) {
    const List<String> presetCommands = [
      'RESET',
      'SEED',
      'GLIDER',
      'BLINKER',
      'SPEED:100',
      'SPEED:300',
      'BRIGHT:50',
      'BRIGHT:200',
      'LIMIT:800',
      'LIMIT:1000',
      'ON',
      'OFF',
      'GET_BOARD',
    ];

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.terminal, color: Colors.cyanAccent, size: 20),
                SizedBox(width: 8),
                Text(
                  'Send Command Console',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Send discrete BLE / Serial commands on demand to the ESP32 matrix.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),

            // Command input text field with Send Button
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customCmdController,
                    decoration: InputDecoration(
                      hintText: 'e.g. SPEED:250, GLIDER, BRIGHT:100',
                      hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.cyanAccent),
                      ),
                    ),
                    onSubmitted: (val) {
                      _sendCustomCommand(val);
                      _customCmdController.clear();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    _sendCustomCommand(_customCmdController.text);
                    _customCmdController.clear();
                  },
                  icon: const Icon(Icons.send, size: 18),
                  label: const Text('Send', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Quick Preset Command Chips
            const Text(
              'Quick Command Presets:',
              style: TextStyle(fontSize: 11, color: Colors.white54, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: presetCommands.map((cmd) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6.0),
                    child: ActionChip(
                      label: Text(cmd, style: const TextStyle(fontSize: 11)),
                      backgroundColor: Colors.cyan.withValues(alpha: 0.12),
                      side: BorderSide(color: Colors.cyan.withValues(alpha: 0.3)),
                      onPressed: () => _sendCustomCommand(cmd),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
