import 'package:flutter/material.dart';

import '../models/polygon_style.dart';
import 'extrusion_geometry.dart';

/// A selected polygon projected to screen space and ready to be extruded.
class ExtrudedShape {
  /// Screen-space footprint rings (outer ring first, then holes).
  final List<List<Offset>> footprint;

  /// Screen offset from the footprint to the roof (points up on screen).
  final Offset lift;

  /// Walls sorted back to front.
  final List<ExtrusionWall> walls;

  /// Style the roof and wall colors are derived from.
  final PolygonStyle style;

  ExtrudedShape({
    required this.footprint,
    required this.lift,
    required this.style,
  }) : walls = ExtrusionGeometry.buildWalls(footprint, lift);

  /// Deepest (closest to the viewer) footprint y, used to order shapes.
  double get maxY => footprint.first.fold(
    double.negativeInfinity,
    (m, p) => p.dy > m ? p.dy : m,
  );
}

/// Paints [ExtrudedShape]s as 2.5D blocks: shaded walls back to front, then
/// the roof (even-odd filled so holes stay open) and its outline.
class GeoExtrusionPainter extends CustomPainter {
  /// Shapes to paint, sorted back to front.
  final List<ExtrudedShape> shapes;

  GeoExtrusionPainter(List<ExtrudedShape> shapes)
    : shapes = [...shapes]..sort((a, b) => a.maxY.compareTo(b.maxY));

  /// Roof color: the style fill made opaque over white so back walls do not
  /// bleed through a translucent fill.
  static Color roofColor(PolygonStyle style) =>
      Color.alphaBlend(style.color, Colors.white);

  /// Wall color for a lighting [shade] in `[0, 1]`: a darker shade of the
  /// roof, lighter for walls facing the light.
  static Color wallColor(PolygonStyle style, double shade) {
    final base = HSLColor.fromColor(roofColor(style));
    final lit = _darken(base, 0.12);
    final dark = _darken(base, 0.42);
    return Color.lerp(dark, lit, shade)!;
  }

  static Color _darken(HSLColor color, double amount) => color
      .withLightness((color.lightness * (1 - amount)).clamp(0.0, 1.0))
      .toColor();

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..style = PaintingStyle.fill;

    for (final shape in shapes) {
      final style = shape.style;

      for (final wall in shape.walls) {
        fill.color = wallColor(style, wall.shade);
        canvas.drawPath(Path()..addPolygon(wall.quad, true), fill);
      }

      final roof = Path()..fillType = PathFillType.evenOdd;
      for (final ring in shape.footprint) {
        roof.addPolygon(ring.map((p) => p + shape.lift).toList(), true);
      }
      fill.color = roofColor(style);
      canvas.drawPath(roof, fill);

      if (style.borderStrokeWidth > 0) {
        canvas.drawPath(
          roof,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = style.borderStrokeWidth
            ..strokeJoin = StrokeJoin.round
            ..color = style.borderColor,
        );
      }

      final label = style.label;
      if (label != null && label.isNotEmpty) {
        _paintLabel(canvas, shape, label);
      }
    }
  }

  void _paintLabel(Canvas canvas, ExtrudedShape shape, String label) {
    final outer = shape.footprint.first;
    var centroid = Offset.zero;
    for (final p in outer) {
      centroid += p;
    }
    centroid = centroid / outer.length.toDouble() + shape.lift;

    final painter = TextPainter(
      text: TextSpan(text: label, style: shape.style.labelStyle),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout();
    painter.paint(
      canvas,
      centroid - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  @override
  // Shapes are re-projected on every camera change, so always repaint.
  bool shouldRepaint(covariant GeoExtrusionPainter oldDelegate) => true;
}
