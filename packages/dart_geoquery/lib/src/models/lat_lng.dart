import 'dart:math' as math;

/// Represents a geographic coordinate in latitude and longitude (WGS 84).
class LatLng {
  final double latitude;
  final double longitude;

  const LatLng(this.latitude, this.longitude)
      : assert(latitude >= -90.0 && latitude <= 90.0,
            'Latitude must be between -90 and 90 degrees'),
        assert(longitude >= -180.0 && longitude <= 180.0,
            'Longitude must be between -180 and 180 degrees');

  /// Distance in meters to another [LatLng] using the Haversine formula.
  double distanceTo(LatLng other) {
    const earthRadiusMeters = 6371000.0;
    final dLat = _toRadians(other.latitude - latitude);
    final dLon = _toRadians(other.longitude - longitude);

    final lat1 = _toRadians(latitude);
    final lat2 = _toRadians(other.latitude);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.sin(dLon / 2) *
            math.sin(dLon / 2) *
            math.cos(lat1) *
            math.cos(lat2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  static double _toRadians(double degree) => degree * math.pi / 180.0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LatLng &&
          runtimeType == other.runtimeType &&
          (latitude - other.latitude).abs() < 1e-9 &&
          (longitude - other.longitude).abs() < 1e-9;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'LatLng($latitude, $longitude)';
}
