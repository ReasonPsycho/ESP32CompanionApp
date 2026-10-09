import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

enum SoilVisualizerStyle {
  pot,
  gauge,
  calibration,
}

class SoilVisualizer extends StatefulWidget {
  final SensorData data;
  final SoilVisualizerStyle initialStyle;
  final bool showControls;
  final ValueChanged<double>? onDryVoltChanged;
  final ValueChanged<double>? onWetVoltChanged;
  final VoidCallback? onCalibrateCurrentDry;
  final VoidCallback? onCalibrateCurrentWet;
  final VoidCallback? onResetCalibration;
  final Function(double dry, double wet)? onCalibrationSaved;

  const SoilVisualizer({
    super.key,
    required this.data,
    this.initialStyle = SoilVisualizerStyle.pot,
    this.showControls = true,
    this.onDryVoltChanged,
    this.onWetVoltChanged,
    this.onCalibrateCurrentDry,
    this.onCalibrateCurrentWet,
    this.onResetCalibration,
    this.onCalibrationSaved,
  });

  @override
  State<SoilVisualizer> createState() => _SoilVisualizerState();
}

class _SoilVisualizerState extends State<SoilVisualizer> {
  late SoilVisualizerStyle _style;

  @override
  void initState() {
    super.initState();
    _style = widget.initialStyle;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showControls)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: SegmentedButton<SoilVisualizerStyle>(
              segments: const [
                ButtonSegment(
                  value: SoilVisualizerStyle.pot,
                  icon: Icon(Icons.water_drop),
                  label: Text('Soil Pot'),
                ),
                ButtonSegment(
                  value: SoilVisualizerStyle.gauge,
                  icon: Icon(Icons.speed),
                  label: Text('Gauge'),
                ),
                ButtonSegment(
                  value: SoilVisualizerStyle.calibration,
                  icon: Icon(Icons.tune),
                  label: Text('Sensor / Cal'),
                ),
              ],
              selected: {_style},
              onSelectionChanged: (newSelection) {
                setState(() => _style = newSelection.first);
              },
            ),
          ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildVisualizerContent(context),
        ),
      ],
    );
  }

  Widget _buildVisualizerContent(BuildContext context) {
    final pct = widget.data.soilPercent ?? 0.0;
    final volt = widget.data.soilVoltage;
    final raw = widget.data.soilRaw;
    final dry = widget.data.dryVolt;
    final wet = widget.data.wetVolt;

    switch (_style) {
      case SoilVisualizerStyle.pot:
        return SoilPotCard(percent: pct, voltage: volt, raw: raw);
      case SoilVisualizerStyle.gauge:
        return SoilGaugeCard(percent: pct, voltage: volt, raw: raw);
      case SoilVisualizerStyle.calibration:
        return SoilCalibrationCard(
          percent: pct,
          voltage: volt,
          raw: raw,
          dryVolt: dry,
          wetVolt: wet,
          onDryVoltChanged: widget.onDryVoltChanged,
          onWetVoltChanged: widget.onWetVoltChanged,
          onCalibrateCurrentDry: widget.onCalibrateCurrentDry ?? () {
            setState(() {
              widget.data.calibrateDry();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Dry air point calibrated to ${(widget.data.soilVoltage ?? widget.data.dryVolt).toStringAsFixed(2)} V'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.teal,
              ),
            );
          },
          onCalibrateCurrentWet: widget.onCalibrateCurrentWet ?? () {
            setState(() {
              widget.data.calibrateWet();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Wet water point calibrated to ${(widget.data.soilVoltage ?? widget.data.wetVolt).toStringAsFixed(2)} V'),
                duration: const Duration(seconds: 2),
                backgroundColor: Colors.blueAccent,
              ),
            );
          },
          onResetCalibration: widget.onResetCalibration ?? () {
            setState(() {
              widget.data.resetCalibration();
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sensor calibration reset to factory defaults (1.78V / 0.95V)'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          onCalibrationSaved: widget.onCalibrationSaved ?? (d, w) {
            setState(() {
              widget.data.setCalibration(d, w);
            });
          },
        );
    }
  }
}

/// 1. Soil Pot & Water Reservoir Graphic
class SoilPotCard extends StatelessWidget {
  final double percent;
  final double? voltage;
  final int? raw;

  const SoilPotCard({
    super.key,
    required this.percent,
    this.voltage,
    this.raw,
  });

  Color _getSoilMoistureColor(double pct) {
    if (pct < 20) return const Color(0xFFE65100); // Dry orange/brown
    if (pct < 40) return const Color(0xFFFBC02D); // Yellow moderate
    if (pct <= 75) return const Color(0xFF00ACC1); // Ideal Cyan/Green
    return const Color(0xFF1976D2); // High moisture / saturated Blue
  }

  String _getSoilStatusText(double pct) {
    if (pct < 20) return 'Very Dry (Needs Water)';
    if (pct < 40) return 'Moderate (Dry Soil)';
    if (pct <= 75) return 'Optimal Moisture';
    return 'Very Wet / Saturated';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final color = _getSoilMoistureColor(percent);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.water_drop, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Soil Capacitive Moisture',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.5)),
                  ),
                  child: Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Soil Container & Water Level Cross-Section Visual
            Container(
              width: 190,
              height: 120,
              decoration: BoxDecoration(
                color: isDark ? Colors.brown.shade900.withValues(alpha: 0.5) : const Color(0xFFD7CCC8),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                border: Border.all(
                  color: isDark ? Colors.brown.shade300 : const Color(0xFF8D6E63),
                  width: 3.5,
                ),
              ),
              child: Stack(
                children: [
                  // Liquid / Moisture fill layer
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: FractionallySizedBox(
                      heightFactor: (percent / 100.0).clamp(0.02, 1.0),
                      widthFactor: 1.0,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              color.withValues(alpha: 0.7),
                              color.withValues(alpha: 0.95),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(16),
                            bottomRight: Radius.circular(16),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Soil capacitive sensor probe icon / graphic
                  Positioned(
                    top: 8,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.sensors, color: Colors.cyanAccent, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              'SEN0193 Probe',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Center percentage
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        Icon(
                          percent > 40 ? Icons.eco : Icons.grass,
                          color: percent > 40 ? Colors.greenAccent : Colors.amberAccent,
                          size: 26,
                        ),
                        Text(
                          '${percent.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: const [
                              Shadow(color: Colors.black87, blurRadius: 4),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            // Metrics row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricChip(
                  context,
                  icon: Icons.electric_bolt,
                  label: 'Sensor Volt',
                  value: voltage != null ? '${voltage!.toStringAsFixed(2)} V' : '---',
                  color: Colors.cyan,
                ),
                _buildMetricChip(
                  context,
                  icon: Icons.eco,
                  label: 'Condition',
                  value: _getSoilStatusText(percent),
                  color: color,
                ),
                _buildMetricChip(
                  context,
                  icon: Icons.numbers,
                  label: 'Raw ADC',
                  value: raw != null ? '$raw' : '---',
                  color: Colors.tealAccent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// 2. Soil Moisture Radial Gauge
class SoilGaugeCard extends StatelessWidget {
  final double percent;
  final double? voltage;
  final int? raw;

  const SoilGaugeCard({
    super.key,
    required this.percent,
    this.voltage,
    this.raw,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                const Icon(Icons.speed, color: Colors.cyan, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Soil Moisture Gauge',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              width: 170,
              child: CustomPaint(
                painter: _SoilGaugePainter(
                  percent: percent,
                  theme: theme,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.water_drop, color: Colors.cyanAccent, size: 24),
                      Text(
                        '${percent.toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (voltage != null)
                        Text(
                          '${voltage!.toStringAsFixed(2)} V',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dry (<20%)', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                Text('Optimal (40-75%)', style: TextStyle(fontSize: 12, color: Colors.green.shade600)),
                Text('Wet (>75%)', style: TextStyle(fontSize: 12, color: Colors.blue.shade600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SoilGaugePainter extends CustomPainter {
  final double percent;
  final ThemeData theme;

  _SoilGaugePainter({required this.percent, required this.theme});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;
    const startAngle = 0.75 * math.pi; // 135 deg
    const sweepTotalAngle = 1.5 * math.pi; // 270 deg

    // Background track
    final bgPaint = Paint()
      ..color = theme.colorScheme.surfaceContainerHighest
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepTotalAngle,
      false,
      bgPaint,
    );

    // Active progress arc with gradient
    final progressSweep = (percent / 100.0).clamp(0.0, 1.0) * sweepTotalAngle;

    final progressPaint = Paint()
      ..shader = const SweepGradient(
        colors: [Colors.orangeAccent, Colors.yellowAccent, Colors.greenAccent, Colors.blueAccent],
        stops: [0.0, 0.25, 0.6, 0.85],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;

    if (progressSweep > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        progressSweep,
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SoilGaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.theme != theme;
  }
}

/// 3. Soil Capacitive Sensor Calibration & Diagnostic Card
class SoilCalibrationCard extends StatelessWidget {
  final double percent;
  final double? voltage;
  final int? raw;
  final double dryVolt;
  final double wetVolt;
  final ValueChanged<double>? onDryVoltChanged;
  final ValueChanged<double>? onWetVoltChanged;
  final VoidCallback? onCalibrateCurrentDry;
  final VoidCallback? onCalibrateCurrentWet;
  final VoidCallback? onResetCalibration;
  final Function(double dry, double wet)? onCalibrationSaved;

  const SoilCalibrationCard({
    super.key,
    required this.percent,
    this.voltage,
    this.raw,
    this.dryVolt = 1.78,
    this.wetVolt = 0.95,
    this.onDryVoltChanged,
    this.onWetVoltChanged,
    this.onCalibrateCurrentDry,
    this.onCalibrateCurrentWet,
    this.onResetCalibration,
    this.onCalibrationSaved,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volt = voltage ?? (dryVolt - (percent / 100.0) * (dryVolt - wetVolt));

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.blueAccent, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      'Capacitive Sensor Calibration',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.settings_suggest, color: Colors.blueAccent),
                  tooltip: 'Tune Calibration & Presets',
                  onPressed: () => _showTuningSheet(context, theme),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildDetailRow(
              'Sensor Model',
              'DFRobot SEN0193 / Analog Capacitive',
              Icons.memory,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'Dry Air Calibration (SOIL_DRY_VOLT)',
              '${dryVolt.toStringAsFixed(2)} V (0% Moisture)',
              Icons.cloud_off,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'Water Immersion (SOIL_WET_VOLT)',
              '${wetVolt.toStringAsFixed(2)} V (100% Moisture)',
              Icons.water,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'Current Sensor Voltage',
              '${volt.toStringAsFixed(3)} V',
              Icons.electric_meter,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'ADC Raw Reading (12-bit)',
              raw != null ? '$raw / 4095' : '${(volt / 3.3 * 4095).toInt()} / 4095',
              Icons.tag,
              theme,
            ),
            const SizedBox(height: 14),
            Text(
              'Sensor Voltage Inverted Calibration Map',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 6),
            // Calibration Bar (dryVolt on left = 0%, wetVolt on right = 100%)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((dryVolt - volt) / ((dryVolt - wetVolt).abs() < 0.001 ? 0.001 : (dryVolt - wetVolt))).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyan),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Dry: ${dryVolt.toStringAsFixed(2)}V', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                Text('Mid: ${((dryVolt + wetVolt) / 2).toStringAsFixed(2)}V', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
                Text('Wet: ${wetVolt.toStringAsFixed(2)}V', style: TextStyle(fontSize: 11, color: theme.colorScheme.outline)),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // --- Interactive Calibration Action Buttons ---
            Text(
              'Interactive 2-Point Live Calibration',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Hold probe in dry air or submerge in water to capture reference levels:',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_off, size: 18),
                    label: const Text('Set as Dry (0%)', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      foregroundColor: Colors.orange.shade800,
                    ),
                    onPressed: onCalibrateCurrentDry,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.water, size: 18),
                    label: const Text('Set as Wet (100%)', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                      foregroundColor: Colors.blue.shade700,
                    ),
                    onPressed: onCalibrateCurrentWet,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Tune & Presets', style: TextStyle(fontSize: 12)),
                    onPressed: () => _showTuningSheet(context, theme),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Reset', style: TextStyle(fontSize: 12)),
                  onPressed: onResetCalibration,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTuningSheet(BuildContext context, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return _SoilCalibrationTuningSheet(
          currentVoltage: voltage ?? dryVolt,
          initialDryVolt: dryVolt,
          initialWetVolt: wetVolt,
          onSave: onCalibrationSaved,
          onReset: onResetCalibration,
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// Modal Bottom Sheet for Manual Threshold Calibration and Sensor Presets
class _SoilCalibrationTuningSheet extends StatefulWidget {
  final double currentVoltage;
  final double initialDryVolt;
  final double initialWetVolt;
  final Function(double dry, double wet)? onSave;
  final VoidCallback? onReset;

  const _SoilCalibrationTuningSheet({
    required this.currentVoltage,
    required this.initialDryVolt,
    required this.initialWetVolt,
    this.onSave,
    this.onReset,
  });

  @override
  State<_SoilCalibrationTuningSheet> createState() => _SoilCalibrationTuningSheetState();
}

class _SoilCalibrationTuningSheetState extends State<_SoilCalibrationTuningSheet> {
  late double _dryVolt;
  late double _wetVolt;

  @override
  void initState() {
    super.initState();
    _dryVolt = widget.initialDryVolt;
    _wetVolt = widget.initialWetVolt;
  }

  void _applyPreset(double dry, double wet) {
    setState(() {
      _dryVolt = dry;
      _wetVolt = wet;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denom = (_dryVolt - _wetVolt).abs() < 0.001 ? 0.001 : (_dryVolt - _wetVolt);
    final estimatedPct = ((_dryVolt - widget.currentVoltage) / denom * 100.0).clamp(0.0, 100.0);

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Icon(Icons.tune, color: Colors.cyan, size: 24),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          'Sensor Calibration Options',
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Adjust the dry air and saturated water reference voltages to calibrate your sensor.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 16),

            // Sensor Presets Section
            Text('Quick Sensor Presets', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.memory, size: 16),
                  label: const Text('SEN0193 (1.78V / 0.95V)'),
                  onPressed: () => _applyPreset(1.78, 0.95),
                ),
                ActionChip(
                  avatar: const Icon(Icons.bolt, size: 16),
                  label: const Text('3.3V Resistive (3.00V / 1.20V)'),
                  onPressed: () => _applyPreset(3.00, 1.20),
                ),
                ActionChip(
                  avatar: const Icon(Icons.precision_manufacturing, size: 16),
                  label: const Text('High-Sensitivity (2.20V / 1.10V)'),
                  onPressed: () => _applyPreset(2.20, 1.10),
                ),
                ActionChip(
                  avatar: const Icon(Icons.water_drop, size: 16),
                  label: const Text('Wide-Range (2.50V / 0.80V)'),
                  onPressed: () => _applyPreset(2.50, 0.80),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Live preview box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      const Text('Live Voltage', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('${widget.currentVoltage.toStringAsFixed(3)} V',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ],
                  ),
                  const Icon(Icons.arrow_forward, color: Colors.cyan),
                  Column(
                    children: [
                      const Text('Calibrated Moisture', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text('${estimatedPct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.cyan)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Dry Air Voltage Slider (0% Moisture)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Dry Air Voltage (0% Moisture)', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_dryVolt.toStringAsFixed(2)} V', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
              ],
            ),
            Slider(
              value: _dryVolt.clamp(1.0, 3.3),
              min: 1.0,
              max: 3.3,
              divisions: 46,
              label: '${_dryVolt.toStringAsFixed(2)} V',
              activeColor: Colors.orange,
              onChanged: (val) {
                setState(() => _dryVolt = double.parse(val.toStringAsFixed(2)));
              },
            ),
            const SizedBox(height: 12),

            // Wet Water Voltage Slider (100% Moisture)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Water Immersion (100% Moisture)', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('${_wetVolt.toStringAsFixed(2)} V', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
              ],
            ),
            Slider(
              value: _wetVolt.clamp(0.2, 2.5),
              min: 0.2,
              max: 2.5,
              divisions: 46,
              label: '${_wetVolt.toStringAsFixed(2)} V',
              activeColor: Colors.blue,
              onChanged: (val) {
                setState(() => _wetVolt = double.parse(val.toStringAsFixed(2)));
              },
            ),
            const SizedBox(height: 24),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.restore),
                    label: const Text('Reset Factory'),
                    onPressed: () {
                      _applyPreset(1.78, 0.95);
                      widget.onReset?.call();
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: const Text('Apply Calibration'),
                    onPressed: () {
                      widget.onSave?.call(_dryVolt, _wetVolt);
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Calibration applied: Dry=${_dryVolt.toStringAsFixed(2)}V, Wet=${_wetVolt.toStringAsFixed(2)}V'),
                          backgroundColor: Colors.teal,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper function to display the sensor calibration dialog from anywhere in the app
Future<void> showSensorCalibrationDialog(
  BuildContext context, {
  required SensorData sensorData,
  Function(double dry, double wet)? onSave,
  VoidCallback? onCalibrateDry,
  VoidCallback? onCalibrateWet,
  VoidCallback? onReset,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _SoilCalibrationTuningSheet(
        currentVoltage: sensorData.soilVoltage ?? sensorData.dryVolt,
        initialDryVolt: sensorData.dryVolt,
        initialWetVolt: sensorData.wetVolt,
        onSave: onSave ?? (d, w) => sensorData.setCalibration(d, w),
        onReset: onReset ?? () => sensorData.resetCalibration(),
      );
    },
  );
}
