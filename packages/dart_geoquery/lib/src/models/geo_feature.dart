import 'lat_lng.dart';

/// Represents a geospatial feature extracted from a vector tile.
class GeoFeature {
  /// Unique identifier of the feature, if available in the tile.
  final int? id;

  /// Name of the layer this feature belongs to (e.g. 'barrios', 'roads').
  final String layer;

  /// Attributes/properties associated with this feature.
  final Map<String, dynamic> properties;

  /// Raw geometry type (e.g. 'Point', 'LineString', 'Polygon').
  final String geometryType;

  /// Projected WGS84 polygon rings (outer ring followed by hole rings).
  final List<List<LatLng>>? coordinates;

  /// Whether any vertex of this geometry touches or extends beyond the tile boundary.
  final bool touchesTileBoundary;

  /// Candidate relative tile offsets `(dx, dy)` based on the specific edges touched.
  final List<(int dx, int dy)> candidateNeighborOffsets;

  /// The tile coordinate `(x, y, z)` where this feature was located.
  final (int x, int y, int z)? sourceTile;

  const GeoFeature({
    this.id,
    required this.layer,
    required this.properties,
    required this.geometryType,
    this.coordinates,
    this.touchesTileBoundary = false,
    this.candidateNeighborOffsets = const [],
    this.sourceTile,
  });

  /// Convenient access to feature attributes, e.g. `feature['name']`.
  dynamic operator [](String key) => properties[key];

  /// Returns typed value for [key] or `null` if not present.
  T? get<T>(String key) {
    final value = properties[key];
    if (value is T) return value;
    return null;
  }

  GeoFeature copyWith({
    int? id,
    String? layer,
    Map<String, dynamic>? properties,
    String? geometryType,
    List<List<LatLng>>? coordinates,
    bool? touchesTileBoundary,
    List<(int dx, int dy)>? candidateNeighborOffsets,
    (int x, int y, int z)? sourceTile,
  }) {
    return GeoFeature(
      id: id ?? this.id,
      layer: layer ?? this.layer,
      properties: properties ?? this.properties,
      geometryType: geometryType ?? this.geometryType,
      coordinates: coordinates ?? this.coordinates,
      touchesTileBoundary: touchesTileBoundary ?? this.touchesTileBoundary,
      candidateNeighborOffsets:
          candidateNeighborOffsets ?? this.candidateNeighborOffsets,
      sourceTile: sourceTile ?? this.sourceTile,
    );
  }

  @override
  String toString() =>
      'GeoFeature(id: $id, layer: $layer, geometryType: $geometryType, touchesBoundary: $touchesTileBoundary, properties: $properties)';
}
