import 'package:flutter/material.dart';
import '../models/led_matrix_data.dart';

class LedMatrixDisplay extends StatefulWidget {
  final LedMatrixData data;
  final bool isInteractiveDraw;
  final Color selectedDrawColor;
  final Function(int x, int y, Color color)? onPixelDrawn;
  final double size;

  const LedMatrixDisplay({
    super.key,
    required this.data,
    this.isInteractiveDraw = false,
    this.selectedDrawColor = const Color(0xFF00FF00),
    this.onPixelDrawn,
    this.size = 280.0,
  });

  @override
  State<LedMatrixDisplay> createState() => _LedMatrixDisplayState();
}

class _LedMatrixDisplayState extends State<LedMatrixDisplay> {
  int? _hoveredPixel;

  void _handleTouch(Offset localPos) {
    if (!widget.isInteractiveDraw || widget.onPixelDrawn == null) return;
    final cellSize = widget.size / LedMatrixData.gridSize;
    final int x = (localPos.dx / cellSize).floor().clamp(0, LedMatrixData.gridSize - 1);
    final int y = (localPos.dy / cellSize).floor().clamp(0, LedMatrixData.gridSize - 1);

    final idx = LedMatrixData.xyToIndex(x, y);
    if (_hoveredPixel != idx) {
      _hoveredPixel = idx;
      widget.onPixelDrawn!(x, y, widget.selectedDrawColor);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: const Color(0xFF101418),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.6),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              if (widget.isInteractiveDraw)
                BoxShadow(
                  color: widget.selectedDrawColor.withValues(alpha: 0.3),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: GestureDetector(
              onPanStart: (details) => _handleTouch(details.localPosition),
              onPanUpdate: (details) => _handleTouch(details.localPosition),
              onPanEnd: (_) => _hoveredPixel = null,
              onTapDown: (details) {
                _hoveredPixel = null;
                _handleTouch(details.localPosition);
              },
              child: CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _LedMatrixPainter(
                  data: widget.data,
                  brightness: widget.data.brightness,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LedMatrixPainter extends CustomPainter {
  final LedMatrixData data;
  final int brightness;

  _LedMatrixPainter({
    required this.data,
    required this.brightness,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double cellSize = size.width / LedMatrixData.gridSize;
    final double radius = cellSize * 0.40;

    // Background PCB grid lines
    final pcbLinePaint = Paint()
      ..color = const Color(0xFF1C2229)
      ..strokeWidth = 1.0;

    for (int i = 1; i < LedMatrixData.gridSize; i++) {
      canvas.drawLine(
        Offset(i * cellSize, 0),
        Offset(i * cellSize, size.height),
        pcbLinePaint,
      );
      canvas.drawLine(
        Offset(0, i * cellSize),
        Offset(size.width, i * cellSize),
        pcbLinePaint,
      );
    }

    final double brightnessScale = (brightness / 255.0).clamp(0.2, 1.0);

    for (int y = 0; y < LedMatrixData.gridSize; y++) {
      for (int x = 0; x < LedMatrixData.gridSize; x++) {
        final int index = LedMatrixData.xyToIndex(x, y);
        final Color rawColor = (index < data.pixels.length)
            ? data.pixels[index]
            : Colors.black;

        final center = Offset(
          x * cellSize + cellSize / 2,
          y * cellSize + cellSize / 2,
        );

        final rawAlpha = (rawColor.a * 255.0).round().clamp(0, 255);
        final rawRed = (rawColor.r * 255.0).round().clamp(0, 255);
        final rawGreen = (rawColor.g * 255.0).round().clamp(0, 255);
        final rawBlue = (rawColor.b * 255.0).round().clamp(0, 255);

        final bool isOff = rawAlpha == 0 ||
            (rawRed == 0 && rawGreen == 0 && rawBlue == 0);

        if (isOff) {
          // Off LED well
          final offBezel = Paint()..color = const Color(0xFF181C20);
          canvas.drawCircle(center, radius, offBezel);

          final offDie = Paint()..color = const Color(0xFF262C33);
          canvas.drawCircle(center, radius * 0.65, offDie);
        } else {
          // Scaled color for brightness
          final scaledColor = Color.fromARGB(
            255,
            (rawRed * brightnessScale).toInt().clamp(0, 255),
            (rawGreen * brightnessScale).toInt().clamp(0, 255),
            (rawBlue * brightnessScale).toInt().clamp(0, 255),
          );

          // Outer diffused glow
          final glowPaint = Paint()
            ..color = scaledColor.withValues(alpha: 0.45)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
          canvas.drawCircle(center, radius * 1.4, glowPaint);

          // LED Bezel
          final bezelPaint = Paint()..color = const Color(0xFF333333);
          canvas.drawCircle(center, radius, bezelPaint);

          // LED Lens Gradient
          final lensGradient = RadialGradient(
            colors: [
              Colors.white.withValues(alpha: 0.9),
              scaledColor,
              scaledColor.withValues(alpha: 0.8),
            ],
            stops: const [0.0, 0.4, 1.0],
          );

          final lensPaint = Paint()
            ..shader = lensGradient.createShader(
              Rect.fromCircle(center: center, radius: radius * 0.85),
            );
          canvas.drawCircle(center, radius * 0.85, lensPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _LedMatrixPainter oldDelegate) {
    return true;
  }
}
