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

  const GeoFeature({
    this.id,
    required this.layer,
    required this.properties,
    required this.geometryType,
  });

  /// Convenient access to feature attributes, e.g. `feature['name']`.
  dynamic operator [](String key) => properties[key];

  /// Returns typed value for [key] or `null` if not present.
  T? get<T>(String key) {
    final value = properties[key];
    if (value is T) return value;
    return null;
  }

  @override
  String toString() =>
      'GeoFeature(id: $id, layer: $layer, geometryType: $geometryType, properties: $properties)';
}
