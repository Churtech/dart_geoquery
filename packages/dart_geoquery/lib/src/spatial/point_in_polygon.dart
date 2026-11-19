/// High-performance 2D Point-in-Polygon (PIP) and geometric intersection tests.
class PointInPolygon {
  /// Tests if point `(px, py)` is inside a 2D polygon defined by rings.
  ///
  /// [rings] is a list of rings:
  /// - `rings[0]` is the exterior ring (outer boundary).
  /// - `rings[1...]` are interior rings (holes), if any.
  ///
  /// Each ring is a list of points `[x, y]`.
  static bool containsPoint({
    required double px,
    required double py,
    required List<List<List<double>>> rings,
  }) {
    if (rings.isEmpty) return false;

    final outerRing = rings[0];
    if (outerRing.length < 3) return false;

    // Fast bounding box rejection on outer ring
    if (!_boundingBoxContains(px, py, outerRing)) {
      return false;
    }

    // Ray casting on exterior ring
    if (!_isPointInRing(px, py, outerRing)) {
      return false;
    }

    // If inside outer ring, check that it is NOT inside any interior hole ring
    for (var i = 1; i < rings.length; i++) {
      final holeRing = rings[i];
      if (holeRing.length >= 3) {
        if (_boundingBoxContains(px, py, holeRing) &&
            _isPointInRing(px, py, holeRing)) {
          return false; // Point falls inside a hole
        }
      }
    }

    return true;
  }

  /// Tests if point `(px, py)` is inside any polygon in a MultiPolygon.
  ///
  /// [multiPolygon] is a list of polygons, where each polygon has a list of rings.
  static bool containsPointInMultiPolygon({
    required double px,
    required double py,
    required List<List<List<List<double>>>> multiPolygon,
  }) {
    for (final polygon in multiPolygon) {
      if (containsPoint(px: px, py: py, rings: polygon)) {
        return true;
      }
    }
    return false;
  }

  /// Fast axis-aligned bounding box test.
  static bool _boundingBoxContains(
    double px,
    double py,
    List<List<double>> ring,
  ) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;

    for (final p in ring) {
      final x = p[0];
      final y = p[1];
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    return px >= minX && px <= maxX && py >= minY && py <= maxY;
  }

  /// Ray casting algorithm (Jordan curve theorem) for a single ring.
  static bool _isPointInRing(double px, double py, List<List<double>> ring) {
    var inside = false;
    final n = ring.length;

    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = ring[i][0];
      final yi = ring[i][1];
      final xj = ring[j][0];
      final yj = ring[j][1];

      final intersect = ((yi > py) != (yj > py)) &&
          (px < (xj - xi) * (py - yi) / (yj - yi) + xi);
      if (intersect) {
        inside = !inside;
      }
    }

    return inside;
  }
}
