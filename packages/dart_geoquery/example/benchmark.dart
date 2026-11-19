import 'package:dart_geoquery/dart_geoquery.dart';

void main() async {
  print('================================================================');
  print('           DART_GEOQUERY BENCHMARK: COLD VS WARM QUERIES        ');
  print('================================================================');

  const remoteUrl =
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles';

  print('Initializing GeoQuery with background Isolate worker & LRU cache...');
  final initWatch = Stopwatch()..start();
  final geo = await GeoQuery.open(remoteUrl, useIsolate: true, cacheCapacity: 64);
  initWatch.stop();
  print('Archive opened in: ${initWatch.elapsedMilliseconds} ms (HTTP range request for header & metadata)\n');

  // Exact building coordinate in Wellington (-41.277496, 174.770091)
  const testPoint = LatLng(-41.277496, 174.770091);

  // 1. COLD QUERY (first time: HTTP range fetch tile bytes + MVT decode in isolate + BBox index + PIP)
  final coldWatch = Stopwatch()..start();
  final coldResult = await geo.at(testPoint, layer: 'buildings');
  coldWatch.stop();

  print('❄️  COLD QUERY (Network fetch + Isolate decode + BBox + PIP):');
  print('   Duration: ${coldWatch.elapsedMilliseconds} ms (${coldWatch.elapsedMicroseconds} µs)');
  print('   Result: ${coldResult?['town_city']}, ${coldResult?['suburb_loc']} (ID: ${coldResult?['building_i']})');

  // 2. WARM QUERY (subsequent query: tile already decoded and indexed in Isolate LRU cache)
  final warmWatch = Stopwatch()..start();
  final warmResult = await geo.at(testPoint, layer: 'buildings');
  warmWatch.stop();

  print('\n🔥 WARM QUERY 1 (Isolate in-memory LRU cache hit):');
  print('   Duration: ${warmWatch.elapsedMilliseconds} ms (${warmWatch.elapsedMicroseconds} µs)');
  print('   Result: ${warmResult?['town_city']}, ${warmResult?['suburb_loc']} (ID: ${warmResult?['building_i']})');

  // 3. WARM QUERY 2 (another query to verify consistency)
  final warmWatch2 = Stopwatch()..start();
  await geo.at(testPoint, layer: 'buildings');
  warmWatch2.stop();

  print('\n🔥 WARM QUERY 2:');
  print('   Duration: ${warmWatch2.elapsedMilliseconds} ms (${warmWatch2.elapsedMicroseconds} µs)');

  final speedup = coldWatch.elapsedMicroseconds / warmWatch.elapsedMicroseconds;
  print('\n----------------------------------------------------------------');
  print('⚡ Speedup: ${speedup.toStringAsFixed(1)}x faster on warm cache!');
  print('----------------------------------------------------------------');

  geo.close();
}
