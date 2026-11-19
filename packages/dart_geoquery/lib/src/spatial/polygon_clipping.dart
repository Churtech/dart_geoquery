/// Implementation of the Sutherland-Hodgman polygon clipping algorithm
/// for clipping 2D polygon rings against an axis-aligned rectangular tile boundary.
class PolygonClipping {
  /// Clips a 2D polygon [ring] to the rectangular window `[minX, minY, maxX, maxY]`.
  ///
  /// Each ring is a list of points `[x, y]`.
  /// Returns a new ring with exact boundary intersection vertices.
  static List<List<double>> clipRingToBox(
    List<List<double>> ring, {
    double minX = 0.0,
    double minY = 0.0,
    required double maxX,
    required double maxY,
  }) {
    if (ring.length < 3) return const [];

    // Ensure ring does not have identical closing point during clipping
    final points = List<List<double>>.from(ring);
    if (points.length > 1 &&
        (points.first[0] - points.last[0]).abs() < 1e-9 &&
        (points.first[1] - points.last[1]).abs() < 1e-9) {
      points.removeLast();
    }

    if (points.length < 3) return const [];

    var outputList = points;

    // 1. Clip against left edge: x >= minX
    outputList = _clipAgainstEdge(
      outputList,
      isInside: (p) => p[0] >= minX,
      computeIntersection: (p1, p2) {
        final t = (minX - p1[0]) / (p2[0] - p1[0]);
        final y = p1[1] + t * (p2[1] - p1[1]);
        return [minX, y];
      },
    );

    // 2. Clip against right edge: x <= maxX
    outputList = _clipAgainstEdge(
      outputList,
      isInside: (p) => p[0] <= maxX,
      computeIntersection: (p1, p2) {
        final t = (maxX - p1[0]) / (p2[0] - p1[0]);
        final y = p1[1] + t * (p2[1] - p1[1]);
        return [maxX, y];
      },
    );

    // 3. Clip against top edge: y >= minY
    outputList = _clipAgainstEdge(
      outputList,
      isInside: (p) => p[1] >= minY,
      computeIntersection: (p1, p2) {
        final t = (minY - p1[1]) / (p2[1] - p1[1]);
        final x = p1[0] + t * (p2[0] - p1[0]);
        return [x, minY];
      },
    );

    // 4. Clip against bottom edge: y <= maxY
    outputList = _clipAgainstEdge(
      outputList,
      isInside: (p) => p[1] <= maxY,
      computeIntersection: (p1, p2) {
        final t = (maxY - p1[1]) / (p2[1] - p1[1]);
        final x = p1[0] + t * (p2[0] - p1[0]);
        return [x, maxY];
      },
    );

    if (outputList.length < 3) return const [];

    // Re-close the ring
    return [...outputList, outputList.first];
  }

  /// Sutherland-Hodgman step against a single half-plane.
  static List<List<double>> _clipAgainstEdge(
    List<List<double>> inputList, {
    required bool Function(List<double> p) isInside,
    required List<double> Function(List<double> p1, List<double> p2)
        computeIntersection,
  }) {
    if (inputList.isEmpty) return const [];

    final output = <List<double>>[];
    var prev = inputList.last;
    var prevInside = isInside(prev);

    for (final curr in inputList) {
      final currInside = isInside(curr);

      if (currInside) {
        if (!prevInside) {
          output.add(computeIntersection(prev, curr));
        }
        output.add(curr);
      } else if (prevInside) {
        output.add(computeIntersection(prev, curr));
      }

      prev = curr;
      prevInside = currInside;
    }

    return output;
  }

  /// Calculates polygon area using the Shoelace formula (Gauss's area formula).
  static double computeArea(List<List<double>> ring) {
    if (ring.length < 3) return 0.0;
    var area = 0.0;
    final n = ring.length;

    for (var i = 0; i < n - 1; i++) {
      area += ring[i][0] * ring[i + 1][1] - ring[i + 1][0] * ring[i][1];
    }
    // Also include last-to-first if not closed
    if ((ring.first[0] - ring.last[0]).abs() > 1e-9 ||
        (ring.first[1] - ring.last[1]).abs() > 1e-9) {
      area += ring.last[0] * ring.first[1] - ring.first[0] * ring.last[1];
    }

    return (area / 2.0).abs();
  }
}
