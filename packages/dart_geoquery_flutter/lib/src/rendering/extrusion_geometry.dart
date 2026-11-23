import 'dart:math' as math;
import 'dart:ui';

/// A single extruded wall: a screen-space quad between a footprint edge and
/// the matching roof edge.
class ExtrusionWall {
  /// Quad vertices: `[base start, base end, roof end, roof start]`.
  final List<Offset> quad;

  /// Painting depth (midpoint y of the base edge). Walls with a smaller
  /// depth are farther from the viewer and must be painted first.
  final double depth;

  /// Lighting factor in `[0, 1]`; `1` faces the light (top-left) directly.
  final double shade;

  const ExtrusionWall({
    required this.quad,
    required this.depth,
    required this.shade,
  });
}

/// Pure screen-space helpers used to draw 2.5D extruded polygons.
abstract final class ExtrusionGeometry {
  /// Equatorial circumference of the Web Mercator sphere, in meters.
  static const double earthCircumference = 40075016.686;

  /// Size in pixels of the world at zoom 0 (flutter_map's EPSG:3857 scale).
  static const double tileSize = 256;

  /// Unit vector pointing from a surface towards the light (top-left).
  static const Offset lightDirection = Offset(-math.sqrt1_2, -math.sqrt1_2);

  /// Ground resolution (meters per screen pixel) at [latitude] and [zoom].
  static double metersPerPixel(double latitude, double zoom) =>
      earthCircumference *
      math.cos(latitude * math.pi / 180) /
      (tileSize * math.pow(2, zoom));

  /// Converts a real-world height into the on-screen roof offset in pixels,
  /// scaled by [perspective] to fake an oblique view.
  static double heightToPixels({
    required double heightMeters,
    required double latitude,
    required double zoom,
    double perspective = 0.7,
  }) => heightMeters / metersPerPixel(latitude, zoom) * perspective;

  /// Reads a height in meters from [properties] at [key].
  ///
  /// Accepts numbers and numeric strings; returns [fallback] when the value
  /// is missing, unparsable or not positive.
  static double resolveHeight(
    Map<String, dynamic> properties,
    String key,
    double fallback,
  ) {
    final raw = properties[key];
    final value = switch (raw) {
      num n => n.toDouble(),
      String s => double.tryParse(s.trim()),
      _ => null,
    };
    if (value == null || !value.isFinite || value <= 0) return fallback;
    return value;
  }

  /// Builds the walls of a polygon whose screen-space [rings] (outer ring
  /// first, then holes) are raised by [lift].
  ///
  /// Walls are returned sorted back to front (ascending [ExtrusionWall.depth]).
  /// Rings wound like the first ring are outer parts lit by their outward
  /// normal; rings wound the opposite way are holes whose walls face into
  /// the courtyard.
  static List<ExtrusionWall> buildWalls(List<List<Offset>> rings, Offset lift) {
    final walls = <ExtrusionWall>[];

    double? outerArea;

    for (final ring in rings) {
      if (ring.length < 2) continue;

      final area = _signedArea(ring);
      if (area == 0) continue;
      // The first ring sets the "outer" winding; rings wound the other way
      // are holes. Stitched features carry several outer rings (one per tile
      // piece), so the ring index alone cannot tell holes apart.
      outerArea ??= area;
      final isHole = area.sign != outerArea.sign;
      // In y-down screen space a positive shoelace area means (dy, -dx) is
      // the outward normal. Holes flip it so their walls face inwards.
      final outwardSign = area > 0 ? 1.0 : -1.0;
      final sign = isHole ? -outwardSign : outwardSign;

      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        final d = b - a;
        final length = d.distance;
        if (length == 0) continue;

        final normal = Offset(d.dy, -d.dx) * (sign / length);
        final dot =
            normal.dx * lightDirection.dx + normal.dy * lightDirection.dy;

        walls.add(
          ExtrusionWall(
            quad: [a, b, b + lift, a + lift],
            depth: (a.dy + b.dy) / 2,
            shade: ((dot + 1) / 2).clamp(0.0, 1.0),
          ),
        );
      }
    }

    walls.sort((x, y) => x.depth.compareTo(y.depth));
    return walls;
  }

  static double _signedArea(List<Offset> ring) {
    var sum = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final p = ring[i];
      final q = ring[(i + 1) % ring.length];
      sum += p.dx * q.dy - q.dx * p.dy;
    }
    return sum / 2;
  }
}
