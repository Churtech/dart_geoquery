import 'package:dart_geoquery/dart_geoquery.dart';

void main() async {
  // Demonstration of dart_geoquery API
  print('--- dart_geoquery Example ---');

  // Example coordinate (e.g. Bogota)
  const userLocation = LatLng(4.65, -74.05);
  print('User location: $userLocation');

  // Tile math in action:
  final (tileX, tileY) = TileMath.latLngToTile(userLocation, 14);
  print('Tile at zoom 14: ($tileX, $tileY)');

  final (localX, localY) = TileMath.latLngToTileCoordinates(
    point: userLocation,
    zoom: 14,
    extent: 4096,
  );
  print('Local coordinates inside tile: ($localX, $localY)');

  // In production with a real .pmtiles file:
  // final geo = await GeoQuery.open('zonas.pmtiles');
  // final zona = await geo.at(userLocation, layer: 'barrios');
  // print('Current zone: ${zona?['nombre']}');
}
