import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:latlong2/latlong.dart' as ll;

/// Convenient bidirectional conversions between dart_geoquery and latlong2.
extension GeoQueryLatLngExtension on gq.LatLng {
  ll.LatLng toLatLong2() => ll.LatLng(latitude, longitude);
}

extension LatLong2Extension on ll.LatLng {
  gq.LatLng toGeoQuery() => gq.LatLng(latitude, longitude);
}
