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

  group('PolygonClipping (Sutherland-Hodgman) & Area', () {
    test('clips polygon extending past tile boundary and preserves exact area', () {
      // Original 200x100 rectangle: x from -50 to 150, y from 0 to 100
      // Area = 200 * 100 = 20,000
      final originalRing = [
        [-50.0, 0.0],
        [150.0, 0.0],
        [150.0, 100.0],
        [-50.0, 100.0],
        [-50.0, 0.0],
      ];
      final originalArea = PolygonClipping.computeArea(originalRing);
      expect(originalArea, closeTo(20000.0, 1e-4));

      // Slice 1: inside Tile A [x in 0 to 100] (local [0, 100])
      // Sutherland-Hodgman cuts at x=0 and x=100
      final tileAClip = PolygonClipping.clipRingToBox(
        originalRing,
        minX: 0.0,
        minY: 0.0,
        maxX: 100.0,
        maxY: 100.0,
      );
      // Slice 1 should be [0..100, 0..100] -> area 10,000
      final areaA = PolygonClipping.computeArea(tileAClip);
      expect(areaA, closeTo(10000.0, 1e-4));

      // Slice 2: inside Tile B (left neighbor: x in -100 to 0)
      final tileBClip = PolygonClipping.clipRingToBox(
        originalRing,
        minX: -100.0,
        minY: 0.0,
        maxX: 0.0,
        maxY: 100.0,
      );
      // Slice 2 should be [-50..0, 0..100] -> area 5,000
      final areaB = PolygonClipping.computeArea(tileBClip);
      expect(areaB, closeTo(5000.0, 1e-4));

      // Slice 3: inside Tile C (right neighbor: x in 100 to 200)
      final tileCClip = PolygonClipping.clipRingToBox(
        originalRing,
        minX: 100.0,
        minY: 0.0,
        maxX: 200.0,
        maxY: 100.0,
      );
      // Slice 3 should be [100..150, 0..100] -> area 5,000
      final areaC = PolygonClipping.computeArea(tileCClip);
      expect(areaC, closeTo(5000.0, 1e-4));

      // Total sum of non-overlapping clipped slices matches original area perfectly!
      expect(areaA + areaB + areaC, closeTo(originalArea, 1e-4));
    });

    test('corner crossing: 4-tile junction clipping preserves total area', () {
      // 200x200 square centered at tile junction (0, 0): [-100..100] x [-100..100]
      // Area = 40,000
      final square = [
        [-100.0, -100.0],
        [100.0, -100.0],
        [100.0, 100.0],
        [-100.0, 100.0],
        [-100.0, -100.0],
      ];
      final totalArea = PolygonClipping.computeArea(square);
      expect(totalArea, closeTo(40000.0, 1e-4));

      // Quadrant 1 (top-right): [0..100, 0..100]
      final q1 = PolygonClipping.clipRingToBox(
        square,
        minX: 0.0,
        minY: 0.0,
        maxX: 200.0,
        maxY: 200.0,
      );
      // Quadrant 2 (top-left): [-200..0, 0..200]
      final q2 = PolygonClipping.clipRingToBox(
        square,
        minX: -200.0,
        minY: 0.0,
        maxX: 0.0,
        maxY: 200.0,
      );
      // Quadrant 3 (bottom-left): [-200..0, -200..0]
      final q3 = PolygonClipping.clipRingToBox(
        square,
        minX: -200.0,
        minY: -200.0,
        maxX: 0.0,
        maxY: 0.0,
      );
      // Quadrant 4 (bottom-right): [0..200, -200..0]
      final q4 = PolygonClipping.clipRingToBox(
        square,
        minX: 0.0,
        minY: -200.0,
        maxX: 200.0,
        maxY: 0.0,
      );

      final sumArea = PolygonClipping.computeArea(q1) +
          PolygonClipping.computeArea(q2) +
          PolygonClipping.computeArea(q3) +
          PolygonClipping.computeArea(q4);

      expect(sumArea, closeTo(totalArea, 1e-4));
    });

    test('polygon with interior hole crossing border clips outer ring and hole properly', () {
      // Outer: [0..200, 0..200], Hole: [50..150, 50..150]
      // Tile boundary at x = 100
      final outer = [
        [0.0, 0.0],
        [200.0, 0.0],
        [200.0, 200.0],
        [0.0, 200.0],
        [0.0, 0.0],
      ];
      final hole = [
        [50.0, 50.0],
        [150.0, 50.0],
        [150.0, 150.0],
        [50.0, 150.0],
        [50.0, 50.0],
      ];

      // Net area = 200*200 - 100*100 = 30,000
      final netAreaOriginal = PolygonClipping.computeArea(outer) -
          PolygonClipping.computeArea(hole);
      expect(netAreaOriginal, closeTo(30000.0, 1e-4));

      // Left tile [0..100]
      final outerLeft = PolygonClipping.clipRingToBox(outer, maxX: 100.0, maxY: 200.0);
      final holeLeft = PolygonClipping.clipRingToBox(hole, maxX: 100.0, maxY: 200.0);
      final netLeft = PolygonClipping.computeArea(outerLeft) -
          PolygonClipping.computeArea(holeLeft);

      // Right tile [100..200]
      final outerRight = PolygonClipping.clipRingToBox(outer, minX: 100.0, maxX: 200.0, maxY: 200.0);
      final holeRight = PolygonClipping.clipRingToBox(hole, minX: 100.0, maxX: 200.0, maxY: 200.0);
      final netRight = PolygonClipping.computeArea(outerRight) -
          PolygonClipping.computeArea(holeRight);

      expect(netLeft + netRight, closeTo(netAreaOriginal, 1e-4));
    });

    test('stitch depth guard terminates without infinite loops', () async {
      // Create a feature touching boundary with multiple candidate offsets
      const feature = GeoFeature(
        id: 999,
        layer: 'complexes',
        properties: {'name': 'Mega Campus'},
        geometryType: 'Polygon',
        touchesTileBoundary: true,
        candidateNeighborOffsets: [(1, 0), (0, 1), (1, 1)],
        sourceTile: (10, 10, 14),
      );

      // Verify that candidate neighbor offsets are exact to touched directions
      expect(feature.candidateNeighborOffsets.length, equals(3));
      expect(feature.touchesTileBoundary, isTrue);
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

  group('MultiPolygon Querying', () {
    test('isolates matching polygon part in MultiPolygon', () async {
      final query = await GeoQuery.open('../../bogota.pmtiles', useIsolate: true);
      const point = LatLng(4.67098, -74.05507);
      final feat = await query.at(point, layer: 'buildings');
      expect(feat, isNotNull);
      expect(feat!.coordinates, isNotNull);
      // Ring count of the single matched polygon should be 1, not 700+!
      expect(feat.coordinates!.length, lessThan(10));
      // Outer ring should be around the clicked point!
      final outer = feat.coordinates!.first;
      final avgLat = outer.map((p) => p.latitude).reduce((a, b) => a + b) / outer.length;
      final avgLng = outer.map((p) => p.longitude).reduce((a, b) => a + b) / outer.length;
      expect(avgLat, closeTo(point.latitude, 0.005));
      expect(avgLng, closeTo(point.longitude, 0.005));
      query.close();
    });
  });
}
