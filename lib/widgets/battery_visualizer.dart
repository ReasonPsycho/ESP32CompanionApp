import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

enum BatteryVisualizerStyle {
  cell,
  gauge,
  analytics,
}

class BatteryVisualizer extends StatefulWidget {
  final SensorData data;
  final BatteryVisualizerStyle initialStyle;
  final bool showControls;

  const BatteryVisualizer({
    super.key,
    required this.data,
    this.initialStyle = BatteryVisualizerStyle.cell,
    this.showControls = true,
  });

  @override
  State<BatteryVisualizer> createState() => _BatteryVisualizerState();
}

class _BatteryVisualizerState extends State<BatteryVisualizer> {
  late BatteryVisualizerStyle _style;

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
            child: SegmentedButton<BatteryVisualizerStyle>(
              segments: const [
                ButtonSegment(
                  value: BatteryVisualizerStyle.cell,
                  icon: Icon(Icons.battery_charging_full),
                  label: Text('Cell'),
                ),
                ButtonSegment(
                  value: BatteryVisualizerStyle.gauge,
                  icon: Icon(Icons.speed),
                  label: Text('Gauge'),
                ),
                ButtonSegment(
                  value: BatteryVisualizerStyle.analytics,
                  icon: Icon(Icons.analytics_outlined),
                  label: Text('Details'),
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
    final pct = widget.data.batteryPercent ?? 0.0;
    final volt = widget.data.batteryVoltage;

    switch (_style) {
      case BatteryVisualizerStyle.cell:
        return BatteryCellCard(percent: pct, voltage: volt);
      case BatteryVisualizerStyle.gauge:
        return BatteryGaugeCard(percent: pct, voltage: volt);
      case BatteryVisualizerStyle.analytics:
        return BatteryAnalyticsCard(percent: pct, voltage: volt);
    }
  }
}

/// 1. Realistic Battery Cell View
class BatteryCellCard extends StatelessWidget {
  final double percent;
  final double? voltage;

  const BatteryCellCard({
    super.key,
    required this.percent,
    this.voltage,
  });

  Color _getBatteryColor(double pct) {
    if (pct > 50) return const Color(0xFF4CAF50); // Green
    if (pct > 20) return const Color(0xFFFF9800); // Orange
    return const Color(0xFFE53935); // Red
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = _getBatteryColor(percent);
    final isDark = theme.brightness == Brightness.dark;

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.battery_std, color: color, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Battery Level Visualisation',
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
            const SizedBox(height: 20),
            // Custom Animated Battery Graphic
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Battery body
                Container(
                  width: 170,
                  height: 85,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white70 : Colors.black87,
                      width: 3.5,
                    ),
                  ),
                  child: Stack(
                    children: [
                      // Liquid fill bar
                      FractionallySizedBox(
                        widthFactor: (percent / 100.0).clamp(0.01, 1.0),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                color.withValues(alpha: 0.8),
                                color,
                              ],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.4),
                                blurRadius: 8,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                      // Text overlay inside battery
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (percent <= 20)
                              const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20)
                            else if (percent >= 90)
                              const Icon(Icons.bolt, color: Colors.white, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              '${percent.toStringAsFixed(0)}%',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                                shadows: const [
                                  Shadow(
                                    color: Colors.black45,
                                    offset: Offset(1, 1),
                                    blurRadius: 2,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Battery positive terminal (+)
                Container(
                  width: 8,
                  height: 36,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white70 : Colors.black87,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(4),
                      bottomRight: Radius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Voltage and metrics row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricChip(
                  context,
                  icon: Icons.electric_bolt,
                  label: 'Voltage',
                  value: voltage != null ? '${voltage!.toStringAsFixed(3)} V' : '---',
                  color: Colors.blueAccent,
                ),
                _buildMetricChip(
                  context,
                  icon: Icons.health_and_safety,
                  label: 'State',
                  value: _getBatteryStatusText(percent),
                  color: color,
                ),
                _buildMetricChip(
                  context,
                  icon: Icons.battery_charging_full,
                  label: 'Range',
                  value: '3.0 - 4.2V',
                  color: Colors.purpleAccent,
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
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _getBatteryStatusText(double pct) {
    if (pct >= 90) return 'Full';
    if (pct >= 50) return 'Good';
    if (pct >= 20) return 'Normal';
    if (pct >= 10) return 'Low';
    return 'Critical';
  }
}

/// 2. Battery Radial Gauge Card
class BatteryGaugeCard extends StatelessWidget {
  final double percent;
  final double? voltage;

  const BatteryGaugeCard({
    super.key,
    required this.percent,
    this.voltage,
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
                const Icon(Icons.speed, color: Colors.blueAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Radial Battery Gauge',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 170,
              width: 170,
              child: CustomPaint(
                painter: _RadialGaugePainter(
                  percent: percent,
                  theme: theme,
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.bolt, color: Colors.amber, size: 24),
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
                Text('0% (3.0V)', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                Text('50% (3.6V)', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
                Text('100% (4.2V)', style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RadialGaugePainter extends CustomPainter {
  final double percent;
  final ThemeData theme;

  _RadialGaugePainter({required this.percent, required this.theme});

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
        colors: [Colors.redAccent, Colors.orangeAccent, Colors.greenAccent],
        stops: [0.0, 0.4, 0.8],
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
  bool shouldRepaint(covariant _RadialGaugePainter oldDelegate) {
    return oldDelegate.percent != percent || oldDelegate.theme != theme;
  }
}

/// 3. Battery Analytics Details Card
class BatteryAnalyticsCard extends StatelessWidget {
  final double percent;
  final double? voltage;

  const BatteryAnalyticsCard({
    super.key,
    required this.percent,
    this.voltage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final volt = voltage ?? (3.0 + (percent / 100.0) * 1.2);

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Colors.teal, size: 24),
                const SizedBox(width: 8),
                Text(
                  'Battery Diagnostics & Curve',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildDetailRow(
              'Battery Chemistry',
              'LiPo / Li-Ion (1S Single Cell)',
              Icons.science_outlined,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'Measured Cell Voltage',
              '${volt.toStringAsFixed(3)} V',
              Icons.electric_meter,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'State of Charge (SoC)',
              '${percent.toStringAsFixed(1)} %',
              Icons.pie_chart_outline,
              theme,
            ),
            const Divider(),
            _buildDetailRow(
              'Cutoff / Max Voltages',
              '3.00 V (Empty) -> 4.20 V (Full)',
              Icons.swap_horiz,
              theme,
            ),
            const SizedBox(height: 14),
            Text(
              'Voltage Linear Scale',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.outline),
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: ((volt - 3.0) / 1.2).clamp(0.0, 1.0),
                minHeight: 10,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  percent > 50
                      ? Colors.green
                      : (percent > 20 ? Colors.orange : Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
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
