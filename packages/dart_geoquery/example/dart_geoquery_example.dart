import 'dart:typed_data';
import 'package:dart_geoquery/dart_geoquery.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/vector_tile.dart';

void main() async {
  print('=== REAL REMOTE PMTILES QUERY TEST ===');
  const url =
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles';

  // 1. Open PMTiles archive with HTTP Range Requests
  final geo = await GeoQuery.open(url);
  print('Opened archive. Max zoom: ${geo.maxZoom}, Layers: ${geo.layers}');

  // 2. Fetch a real building geometry from the tile to get an exact point inside it
  final archive = await PmTilesArchive.from(url);
  const wellingtonCenter = LatLng(-41.2924, 174.7772);
  final (tileX, tileY) = TileMath.latLngToTile(wellingtonCenter, 14);
  final tileId = ZXY(14, tileX, tileY).toTileId();
  final tile = await archive.tile(tileId);
  final vTile = VectorTile.fromBytes(bytes: Uint8List.fromList(tile.bytes()));
  final layer = vTile.layers.first;
  final feature0 = layer.features.first;
  feature0.decodeGeometry();

  final polygon = feature0.geometry as GeometryPolygon;
  final outerRing = polygon.coordinates[0];

  // Calculate centroid of the building polygon in local tile coordinates
  var sumX = 0.0;
  var sumY = 0.0;
  for (final pt in outerRing) {
    sumX += pt[0];
    sumY += pt[1];
  }
  final centroidLocalX = sumX / outerRing.length;
  final centroidLocalY = sumY / outerRing.length;

  // Convert centroid to real-world LatLng
  final buildingLocation = TileMath.tileCoordinatesToLatLng(
    tileX: tileX,
    tileY: tileY,
    zoom: 14,
    localX: centroidLocalX,
    localY: centroidLocalY,
    extent: layer.extent,
  );

  print('\n[Query 1] What building is located at $buildingLocation?');
  final matched = await geo.at(buildingLocation, layer: 'buildings');

  if (matched != null) {
    print('🎯 MATCH FOUND VIA POINT-IN-POLYGON!');
    print('  Town/City: ${matched['town_city']}');
    print('  Suburb: ${matched['suburb_loc']}');
    print('  Building ID: ${matched['building_i']}');
    print('  Geometry: ${matched.geometryType}');
    print('  All properties: ${matched.properties}');
  } else {
    print('No match found.');
  }

  // 3. Test Point Outside
  print('\n[Query 2] Testing point in ocean/empty space:');
  const emptySpace = LatLng(-41.25, 174.70);
  final noMatch = await geo.at(emptySpace, layer: 'buildings');
  print('Point outside result: $noMatch (expected null)');
}
