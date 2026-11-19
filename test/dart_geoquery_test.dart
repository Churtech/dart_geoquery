import 'package:dart_geoquery/dart_geoquery.dart';
import 'package:test/test.dart';

void main() {
  group('LatLng and Distance', () {
    test('calculates Haversine distance correctly', () {
      // Bogota (~4.6097, -74.0817) to Medellin (~6.2442, -75.5812) is ~240 km
      const bogota = LatLng(4.6097, -74.0817);
      const medellin = LatLng(6.2442, -75.5812);

      final distanceMeters = bogota.distanceTo(medellin);
      final distanceKm = distanceMeters / 1000.0;

      expect(distanceKm, closeTo(246.14, 0.5));
    });

    test('validates coordinate boundaries', () {
      expect(() => LatLng(91.0, 0.0), throwsA(isA<AssertionError>()));
      expect(() => LatLng(0.0, 181.0), throwsA(isA<AssertionError>()));
    });
  });

  group('TileMath', () {
    test('converts (0,0) at zoom 0 to tile (0,0)', () {
      const origin = LatLng(0.0, 0.0);
      final (x, y) = TileMath.latLngToTile(origin, 0);
      expect(x, equals(0));
      expect(y, equals(0));
    });

    test('tile coordinates roundtrip accurately to LatLng', () {
      const original = LatLng(4.65, -74.05);
      const zoom = 14;
      const extent = 4096;

      final (tileX, tileY) = TileMath.latLngToTile(original, zoom);
      final (localX, localY) = TileMath.latLngToTileCoordinates(
        point: original,
        zoom: zoom,
        extent: extent,
      );

      final restored = TileMath.tileCoordinatesToLatLng(
        tileX: tileX,
        tileY: tileY,
        zoom: zoom,
        localX: localX,
        localY: localY,
        extent: extent,
      );

      expect(restored.latitude, closeTo(original.latitude, 1e-4));
      expect(restored.longitude, closeTo(original.longitude, 1e-4));
    });
  });

  group('PointInPolygon', () {
    // 100x100 square: [0,0] to [100,100]
    final squareRings = [
      [
        [0.0, 0.0],
        [100.0, 0.0],
        [100.0, 100.0],
        [0.0, 100.0],
        [0.0, 0.0],
      ]
    ];

    test('point inside outer ring returns true', () {
      final inside = PointInPolygon.containsPoint(
        px: 50.0,
        py: 50.0,
        rings: squareRings,
      );
      expect(inside, isTrue);
    });

    test('point outside outer ring returns false', () {
      final outside = PointInPolygon.containsPoint(
        px: 150.0,
        py: 50.0,
        rings: squareRings,
      );
      expect(outside, isFalse);
    });

    test('point inside interior hole returns false', () {
      // Square [0,0] to [100,100] with a hole [40,40] to [60,60]
      final squareWithHole = [
        [
          [0.0, 0.0],
          [100.0, 0.0],
          [100.0, 100.0],
          [0.0, 100.0],
          [0.0, 0.0],
        ],
        [
          [40.0, 40.0],
          [60.0, 40.0],
          [60.0, 60.0],
          [40.0, 60.0],
          [40.0, 40.0],
        ],
      ];

      // Point inside the hole (50, 50) -> should be false!
      expect(
        PointInPolygon.containsPoint(
          px: 50.0,
          py: 50.0,
          rings: squareWithHole,
        ),
        isFalse,
      );

      // Point inside polygon but outside hole (20, 20) -> should be true!
      expect(
        PointInPolygon.containsPoint(
          px: 20.0,
          py: 20.0,
          rings: squareWithHole,
        ),
        isTrue,
      );
    });

    test('multi-polygon detection', () {
      final multiPolygon = [
        [
          [
            [0.0, 0.0],
            [10.0, 0.0],
            [10.0, 10.0],
            [0.0, 10.0],
            [0.0, 0.0],
          ]
        ],
        [
          [
            [50.0, 50.0],
            [60.0, 50.0],
            [60.0, 60.0],
            [50.0, 60.0],
            [50.0, 50.0],
          ]
        ],
      ];

      expect(
        PointInPolygon.containsPointInMultiPolygon(
          px: 55.0,
          py: 55.0,
          multiPolygon: multiPolygon,
        ),
        isTrue,
      );

      expect(
        PointInPolygon.containsPointInMultiPolygon(
          px: 25.0,
          py: 25.0,
          multiPolygon: multiPolygon,
        ),
        isFalse,
      );
    });

    test('tile boundary: clipped polygon in adjacent tiles detects point on respective side', () {
      // Simulates a building spanning across tile boundary X=10 and X=11 (extent 4096)
      // Tile 10 clipped slice: x from 3900 to 4096 (plus buffer to 4160)
      final tile10ClippedRing = [
        [
          [3900.0, 1000.0],
          [4160.0, 1000.0],
          [4160.0, 1200.0],
          [3900.0, 1200.0],
          [3900.0, 1000.0],
        ]
      ];

      // Tile 11 clipped slice: x from -64 to 200
      final tile11ClippedRing = [
        [
          [-64.0, 1000.0],
          [200.0, 1000.0],
          [200.0, 1200.0],
          [-64.0, 1200.0],
          [-64.0, 1000.0],
        ]
      ];

      // Point A: just inside Tile 10 side (local x = 4050, y = 1100)
      expect(
        PointInPolygon.containsPoint(
          px: 4050.0,
          py: 1100.0,
          rings: tile10ClippedRing,
        ),
        isTrue,
      );

      // Point B: just inside Tile 11 side (local x = 50, y = 1100)
      expect(
        PointInPolygon.containsPoint(
          px: 50.0,
          py: 1100.0,
          rings: tile11ClippedRing,
        ),
        isTrue,
      );
    });
  });

  group('GeoFeature', () {
    test('exposes properties with operator [] and get<T>', () {
      final feature = GeoFeature(
        id: 123,
        layer: 'barrios',
        geometryType: 'Polygon',
        properties: {
          'name': 'Chapinero',
          'area': 1250.5,
          'code': 1102,
        },
      );

      expect(feature['name'], equals('Chapinero'));
      expect(feature.get<String>('name'), equals('Chapinero'));
      expect(feature.get<double>('area'), equals(1250.5));
      expect(feature.get<int>('code'), equals(1102));
      expect(feature.get<String>('unknown'), isNull);
    });
  });

  group('LruCache', () {
    test('evicts least recently used item when capacity exceeded', () {
      final cache = LruCache<String, int>(capacity: 2);
      cache.put('a', 1);
      cache.put('b', 2);
      expect(cache.length, equals(2));

      // Access 'a' to make it most recently used
      expect(cache.get('a'), equals(1));

      // Add 'c', should evict 'b'
      cache.put('c', 3);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('c'), isTrue);
    });
  });
}
