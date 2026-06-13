import 'package:flutter/material.dart';

/// Caixa com borda tracejada arredondada — indica zonas de drop.
class DashedBox extends StatelessWidget {
  const DashedBox({
    super.key,
    required this.child,
    required this.color,
    this.radius = 14,
    this.dash = 5,
    this.gap = 4,
    this.strokeWidth = 1.4,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedRRectPainter(
        color: color,
        radius: radius,
        dash: dash,
        gap: gap,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedRRectPainter extends CustomPainter {
  _DashedRRectPainter({
    required this.color,
    required this.radius,
    required this.dash,
    required this.gap,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double dash;
  final double gap;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final source = Path()..addRRect(rrect);
    final dashed = Path();
    for (final metric in source.computeMetrics()) {
      var dist = 0.0;
      while (dist < metric.length) {
        final end = (dist + dash).clamp(0.0, metric.length);
        dashed.addPath(metric.extractPath(dist, end), Offset.zero);
        dist = end + gap;
      }
    }
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawPath(dashed, paint);
  }

  @override
  bool shouldRepaint(_DashedRRectPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.dash != dash ||
      old.gap != gap ||
      old.strokeWidth != strokeWidth;
}
