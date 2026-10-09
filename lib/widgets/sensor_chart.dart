import 'package:flutter/material.dart';
import '../models/sensor_data.dart';

class SensorTrendChart extends StatelessWidget {
  final SensorData data;
  final String title;
  final bool showBattery;
  final bool showSoil;

  const SensorTrendChart({
    super.key,
    required this.data,
    this.title = 'Live Sensor Telemetry Trends',
    this.showBattery = true,
    this.showSoil = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final history = data.history;

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
                const Icon(Icons.show_chart, color: Colors.indigoAccent, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${history.length} pts',
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.outline,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Legend
            Row(
              children: [
                if (showSoil) ...[
                  _buildLegendItem('Soil Moisture %', Colors.cyan),
                  const SizedBox(width: 16),
                ],
                if (showBattery) ...[
                  _buildLegendItem('Battery %', Colors.green),
                ],
              ],
            ),
            const SizedBox(height: 14),
            // Chart Canvas
            SizedBox(
              height: 180,
              width: double.infinity,
              child: history.isEmpty
                  ? Center(
                      child: Text(
                        'Waiting for sensor telemetry history...',
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                    )
                  : CustomPaint(
                      painter: _ChartPainter(
                        history: history,
                        theme: theme,
                        showBattery: showBattery,
                        showSoil: showSoil,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Past (Oldest)', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
                Text('Now (Live)', style: TextStyle(fontSize: 10, color: theme.colorScheme.outline)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _ChartPainter extends CustomPainter {
  final List<SensorDataPoint> history;
  final ThemeData theme;
  final bool showBattery;
  final bool showSoil;

  _ChartPainter({
    required this.history,
    required this.theme,
    required this.showBattery,
    required this.showSoil,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (history.isEmpty) return;

    final gridPaint = Paint()
      ..color = theme.dividerColor.withValues(alpha: 0.2)
      ..strokeWidth = 1;

    // Draw horizontal grid lines (0%, 25%, 50%, 75%, 100%)
    for (int i = 0; i <= 4; i++) {
      final y = size.height * (i / 4.0);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final double stepX = history.length > 1 ? size.width / (history.length - 1) : size.width;

    // Draw Soil Moisture Line & Area
    if (showSoil) {
      _drawLineAndFill(
        canvas: canvas,
        size: size,
        stepX: stepX,
        color: Colors.cyan,
        values: history.map((p) => p.soilPercent).toList(),
      );
    }

    // Draw Battery Percentage Line & Area
    if (showBattery) {
      _drawLineAndFill(
        canvas: canvas,
        size: size,
        stepX: stepX,
        color: Colors.green,
        values: history.map((p) => p.batteryPercent).toList(),
      );
    }
  }

  void _drawLineAndFill({
    required Canvas canvas,
    required Size size,
    required double stepX,
    required Color color,
    required List<double?> values,
  }) {
    final linePath = Path();
    final fillPath = Path();
    bool hasStarted = false;
    double firstX = 0;
    double lastX = 0;

    for (int i = 0; i < values.length; i++) {
      final val = values[i];
      if (val == null) continue;

      final x = i * stepX;
      final y = size.height - (val.clamp(0.0, 100.0) / 100.0 * size.height);

      if (!hasStarted) {
        linePath.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
        firstX = x;
        hasStarted = true;
      } else {
        linePath.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      lastX = x;
    }

    if (!hasStarted) return;

    fillPath.lineTo(lastX, size.height);
    fillPath.lineTo(firstX, size.height);
    fillPath.close();

    // Draw fill gradient
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.02)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.fill;
    canvas.drawPath(fillPath, fillPaint);

    // Draw line
    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(linePath, linePaint);

    // Draw current endpoint dot
    if (values.isNotEmpty && values.last != null) {
      final lastVal = values.last!;
      final endY = size.height - (lastVal.clamp(0.0, 100.0) / 100.0 * size.height);
      final dotPaint = Paint()..color = color;
      canvas.drawCircle(Offset(lastX, endY), 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChartPainter oldDelegate) {
    return oldDelegate.history.length != history.length ||
        oldDelegate.showBattery != showBattery ||
        oldDelegate.showSoil != showSoil;
  }
}
