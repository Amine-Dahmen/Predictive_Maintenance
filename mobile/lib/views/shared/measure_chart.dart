import 'dart:math' as math;

import 'package:flutter/material.dart';

class MeasurePoint {
  const MeasurePoint(this.time, this.value);

  final DateTime time;
  final double value;
}

/// US-04 : courbe des mesures d'un capteur avec les seuils d'alerte et critique.
/// Un trou de plus de [gap] entre deux mesures (carte hors ligne) coupe la courbe.
class MeasureChart extends StatelessWidget {
  const MeasureChart({
    super.key,
    required this.points,
    this.alertThreshold,
    this.criticalThreshold,
    this.unit = '',
    this.gap = const Duration(minutes: 2),
  });

  final List<MeasurePoint> points;
  final double? alertThreshold;
  final double? criticalThreshold;
  final String unit;
  final Duration gap;

  @override
  Widget build(BuildContext context) {
    if (points.length < 2) {
      return const SizedBox(
        height: 60,
        child: Center(
          child: Text('Pas assez de mesures pour tracer une courbe.'),
        ),
      );
    }
    final values = points.map((p) => p.value);
    final last = points.last;
    return Semantics(
      label:
          'Courbe de ${points.length} mesures, de ${values.reduce(math.min)} à '
          '${values.reduce(math.max)} $unit, dernière valeur ${last.value} $unit',
      child: SizedBox(
        height: 180,
        child: CustomPaint(
          painter: MeasureChartPainter(
            points: points,
            alertThreshold: alertThreshold,
            criticalThreshold: criticalThreshold,
            gap: gap,
            lineColor: Theme.of(context).colorScheme.primary,
            textColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class MeasureChartPainter extends CustomPainter {
  MeasureChartPainter({
    required this.points,
    required this.gap,
    required this.lineColor,
    required this.textColor,
    this.alertThreshold,
    this.criticalThreshold,
  });

  final List<MeasurePoint> points;
  final double? alertThreshold;
  final double? criticalThreshold;
  final Duration gap;
  final Color lineColor;
  final Color textColor;

  /// Bornes de l'axe vertical : mesures et seuils visibles, avec une marge de 10 %.
  static (double, double) range(List<double> values, List<double?> thresholds) {
    final all = [...values, ...thresholds.whereType<double>()];
    var lo = all.reduce(math.min);
    var hi = all.reduce(math.max);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.1;
    return (lo - pad, hi + pad);
  }

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const bottom = 18.0;
    final w = size.width - left;
    final h = size.height - bottom;
    final sorted = [...points]..sort((a, b) => a.time.compareTo(b.time));
    final t0 = sorted.first.time.millisecondsSinceEpoch.toDouble();
    final t1 = math.max(
      sorted.last.time.millisecondsSinceEpoch.toDouble(),
      t0 + 1,
    );
    final (lo, hi) = range(sorted.map((p) => p.value).toList(), [
      alertThreshold,
      criticalThreshold,
    ]);
    double x(DateTime t) =>
        left + (t.millisecondsSinceEpoch - t0) / (t1 - t0) * w;
    double y(double v) => h - (v - lo) / (hi - lo) * h;

    final axis = Paint()
      ..color = textColor.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(left, 0), Offset(left, h), axis);
    canvas.drawLine(Offset(left, h), Offset(size.width, h), axis);
    _label(canvas, _fmt(hi), const Offset(0, 0));
    _label(canvas, _fmt(lo), Offset(0, h - 12));

    void threshold(double? v, Color c) {
      if (v == null) return;
      final p = Paint()
        ..color = c
        ..strokeWidth = 1.2;
      for (var dx = left; dx < size.width; dx += 8) {
        canvas.drawLine(
          Offset(dx, y(v)),
          Offset(math.min(dx + 4, size.width), y(v)),
          p,
        );
      }
    }

    threshold(alertThreshold, Colors.orange);
    threshold(criticalThreshold, Colors.red);

    final line = Paint()
      ..color = lineColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < sorted.length; i++) {
      final p = Offset(x(sorted[i].time), y(sorted[i].value));
      final broken =
          i == 0 || sorted[i].time.difference(sorted[i - 1].time) > gap;
      broken ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path, line);
    _label(canvas, _time(sorted.first.time), Offset(left, h + 3));
    final end = _time(sorted.last.time);
    _label(canvas, end, Offset(size.width - end.length * 6.0, h + 3));
  }

  String _fmt(double v) =>
      v.abs() >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _time(DateTime t) {
    final l = t.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/${l.month.toString().padLeft(2, '0')} '
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  void _label(Canvas canvas, String text, Offset at) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(MeasureChartPainter old) =>
      old.points != points ||
      old.alertThreshold != alertThreshold ||
      old.criticalThreshold != criticalThreshold;
}
