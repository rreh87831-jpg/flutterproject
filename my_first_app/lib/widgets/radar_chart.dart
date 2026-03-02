import 'dart:math';

import 'package:flutter/material.dart';

class RadarChart extends StatelessWidget {
  final List<String> categories;
  final List<double> before;
  final List<double> after;

  const RadarChart({
    super.key,
    required this.categories,
    required this.before,
    required this.after,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _RadarChartPainter(
        categories: categories,
        before: before,
        after: after,
      ),
    );
  }
}

class _RadarChartPainter extends CustomPainter {
  final List<String> categories;
  final List<double> before;
  final List<double> after;

  _RadarChartPainter({
    required this.categories,
    required this.before,
    required this.after,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (categories.isEmpty) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) * 0.34;
    final step = (2 * pi) / categories.length;

    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * (i / 4), gridPaint);
    }

    for (var i = 0; i < categories.length; i++) {
      final angle = i * step - pi / 2;
      final end = Offset(
        center.dx + radius * cos(angle),
        center.dy + radius * sin(angle),
      );
      canvas.drawLine(center, end, gridPaint);
    }

    final beforePaint = Paint()
      ..color = Colors.grey.shade500
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    _drawPolygon(canvas, center, radius, before, step, beforePaint);

    final fillPaint = Paint()
      ..color = Colors.blue.shade200.withOpacity(0.35)
      ..style = PaintingStyle.fill;
    _drawPolygon(canvas, center, radius, after, step, fillPaint);

    final afterPaint = Paint()
      ..color = Colors.blue.shade700
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    _drawPolygon(canvas, center, radius, after, step, afterPaint);

    final labelStyle = TextStyle(
      color: Colors.grey.shade700,
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
    for (var i = 0; i < categories.length; i++) {
      final angle = i * step - pi / 2;
      final p = Offset(
        center.dx + (radius + 22) * cos(angle),
        center.dy + (radius + 22) * sin(angle),
      );
      final tp = TextPainter(
        text: TextSpan(text: categories[i], style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 110);
      tp.paint(canvas, Offset(p.dx - tp.width / 2, p.dy - tp.height / 2));
    }

    _legend(canvas);
  }

  void _drawPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    List<double> values,
    double step,
    Paint paint,
  ) {
    if (values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final v = (values[i] / 100).clamp(0.0, 1.0);
      final angle = i * step - pi / 2;
      final p = Offset(
        center.dx + radius * v * cos(angle),
        center.dy + radius * v * sin(angle),
      );
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  void _legend(Canvas canvas) {
    final beforePaint = Paint()..color = Colors.grey.shade500;
    final afterPaint = Paint()..color = Colors.blue.shade700;
    canvas.drawRect(const Rect.fromLTWH(12, 10, 12, 12), beforePaint);
    canvas.drawRect(const Rect.fromLTWH(12, 30, 12, 12), afterPaint);

    final tp1 = TextPainter(
      text: const TextSpan(text: ' Before', style: TextStyle(color: Colors.black87, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, const Offset(26, 8));

    final tp2 = TextPainter(
      text: const TextSpan(text: ' After', style: TextStyle(color: Colors.black87, fontSize: 12)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp2.paint(canvas, const Offset(26, 28));
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) {
    return oldDelegate.categories != categories || oldDelegate.before != before || oldDelegate.after != after;
  }
}
