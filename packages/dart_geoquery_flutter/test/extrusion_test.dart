import 'dart:math' as math;

import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:dart_geoquery_flutter/dart_geoquery_flutter.dart';
import 'package:dart_geoquery_flutter/src/rendering/extrusion_geometry.dart';
import 'package:dart_geoquery_flutter/src/rendering/extrusion_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  group('ExtrusionGeometry.metersPerPixel', () {
    test('matches Web Mercator ground resolution at the equator', () {
      // 40075016.686 m / 256 px at zoom 0.
      expect(ExtrusionGeometry.metersPerPixel(0, 0), closeTo(156543.03, 0.01));
      expect(ExtrusionGeometry.metersPerPixel(0, 1), closeTo(78271.52, 0.01));
    });

    test('shrinks with the cosine of latitude', () {
      final equator = ExtrusionGeometry.metersPerPixel(0, 16);
      final at60 = ExtrusionGeometry.metersPerPixel(60, 16);
      expect(at60, closeTo(equator * math.cos(60 * math.pi / 180), 1e-9));
    });

    test('heightToPixels applies the perspective factor', () {
      final mpp = ExtrusionGeometry.metersPerPixel(0, 18);
      final px = ExtrusionGeometry.heightToPixels(
        heightMeters: 30,
        latitude: 0,
        zoom: 18,
        perspective: 0.5,
      );
      expect(px, closeTo(30 / mpp * 0.5, 1e-9));
    });
  });

  group('ExtrusionGeometry.resolveHeight', () {
    test('reads numeric and string values', () {
      expect(
        ExtrusionGeometry.resolveHeight({'height': 25}, 'height', 10),
        equals(25),
      );
      expect(
        ExtrusionGeometry.resolveHeight({'height': '12.5'}, 'height', 10),
        equals(12.5),
      );
    });

    test('falls back when missing, invalid or non-positive', () {
      expect(ExtrusionGeometry.resolveHeight({}, 'height', 10), equals(10));
      expect(
        ExtrusionGeometry.resolveHeight({'height': 'x'}, 'height', 10),
        equals(10),
      );
      expect(
        ExtrusionGeometry.resolveHeight({'height': 0}, 'height', 10),
        equals(10),
      );
    });
  });

  group('ExtrusionGeometry.buildWalls', () {
    // Screen-space square (y grows downwards).
    const square = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];

    Offset mid(ExtrusionWall w) => (w.quad[0] + w.quad[1]) / 2;

    test('creates one wall per edge, lifted by the roof offset', () {
      final walls = ExtrusionGeometry.buildWalls([square], const Offset(0, -5));
      expect(walls.length, equals(4));
      for (final wall in walls) {
        expect(wall.quad.length, equals(4));
        expect(wall.quad[3] - wall.quad[0], equals(const Offset(0, -5)));
        expect(wall.quad[2] - wall.quad[1], equals(const Offset(0, -5)));
      }
    });

    test('orders walls back to front (ascending midpoint y)', () {
      final walls = ExtrusionGeometry.buildWalls([square], const Offset(0, -5));
      final ys = walls.map((w) => w.depth).toList();
      final sorted = [...ys]..sort();
      expect(ys, equals(sorted));
      // Top edge (y = 0) first, bottom edge (y = 10) last.
      expect(walls.first.depth, closeTo(0, 1e-9));
      expect(walls.last.depth, closeTo(10, 1e-9));
    });

    test('shades walls facing the top-left light brighter, for either '
        'ring winding', () {
      for (final ring in [square, square.reversed.toList()]) {
        final walls = ExtrusionGeometry.buildWalls([ring], Offset.zero);
        double shadeAt(Offset at) =>
            walls.firstWhere((w) => (mid(w) - at).distance < 1e-9).shade;
        final top = shadeAt(const Offset(5, 0));
        final left = shadeAt(const Offset(0, 5));
        final right = shadeAt(const Offset(10, 5));
        final bottom = shadeAt(const Offset(5, 10));
        expect(top, greaterThan(bottom));
        expect(left, greaterThan(right));
        for (final s in [top, left, right, bottom]) {
          expect(s, inInclusiveRange(0, 1));
        }
      }
    });

    test('hole walls (opposite winding) face into the courtyard', () {
      const outer = [
        Offset(0, 0),
        Offset(30, 0),
        Offset(30, 30),
        Offset(0, 30),
      ];
      // Holes are wound opposite to the outer ring (MVT convention).
      const hole = [
        Offset(10, 10),
        Offset(10, 20),
        Offset(20, 20),
        Offset(20, 10),
      ];
      final walls = ExtrusionGeometry.buildWalls([outer, hole], Offset.zero);
      final holeTop = walls.firstWhere((w) => mid(w) == const Offset(15, 10));
      final holeBottom = walls.firstWhere(
        (w) => mid(w) == const Offset(15, 20),
      );
      // The courtyard's top wall faces down (away from the light).
      expect(holeTop.shade, lessThan(holeBottom.shade));
    });

    test('extra rings with the outer winding are treated as outer parts', () {
      // Stitched features carry one outer ring per tile piece.
      const left = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];
      const right = [
        Offset(10, 0),
        Offset(20, 0),
        Offset(20, 10),
        Offset(10, 10),
      ];
      final walls = ExtrusionGeometry.buildWalls([left, right], Offset.zero);
      final rightTop = walls.firstWhere((w) => mid(w) == const Offset(15, 0));
      final rightBottom = walls.firstWhere(
        (w) => mid(w) == const Offset(15, 10),
      );
      expect(rightTop.shade, greaterThan(rightBottom.shade));
    });
  });

  group('GeoInteractiveLayer extrusion', () {
    const feature = gq.GeoFeature(
      id: 7,
      layer: 'buildings',
      properties: {'height': 40},
      geometryType: 'Polygon',
      coordinates: [
        [
          gq.LatLng(4.6500, -74.0500),
          gq.LatLng(4.6505, -74.0500),
          gq.LatLng(4.6505, -74.0495),
          gq.LatLng(4.6500, -74.0495),
        ],
        [
          gq.LatLng(4.6501, -74.0499),
          gq.LatLng(4.6501, -74.0496),
          gq.LatLng(4.6504, -74.0496),
          gq.LatLng(4.6504, -74.0499),
        ],
      ],
    );

    Future<gq.GeoQuery> openQuery(WidgetTester tester) async {
      final query = await tester.runAsync(
        () => gq.GeoQuery.open('../../bogota.pmtiles', useIsolate: false),
      );
      addTearDown(query!.close);
      return query;
    }

    Widget buildMap(
      gq.GeoQuery query,
      GeoSelectionController controller, {
      required bool extrude,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            options: const MapOptions(
              initialCenter: ll.LatLng(4.65025, -74.04975),
              initialZoom: 17,
            ),
            children: [
              GeoInteractiveLayer(
                query: query,
                layer: 'buildings',
                controller: controller,
                extrude: extrude,
              ),
            ],
          ),
        ),
      );
    }

    bool isExtrusionPaint(Widget w) =>
        w is CustomPaint && w.painter is GeoExtrusionPainter;

    testWidgets('paints an extruded selected feature without errors', (
      tester,
    ) async {
      final query = await openQuery(tester);
      final controller = GeoSelectionController()..select(feature);

      await tester.pumpWidget(buildMap(query, controller, extrude: true));
      await tester.pump();

      expect(tester.takeException(), isNull);
      final paint = find.byWidgetPredicate(isExtrusionPaint);
      expect(paint, findsOneWidget);
      final painter =
          tester.widget<CustomPaint>(paint).painter! as GeoExtrusionPainter;
      expect(painter.shapes.length, equals(1));
      // 4 outer + 4 hole edges.
      expect(painter.shapes.single.walls.length, equals(8));
      // A 40 m building at zoom 17 rises a visible amount (screen up).
      expect(painter.shapes.single.lift.dy, lessThan(-10));
      expect(find.byType(PolygonLayer), findsNothing);
    });

    testWidgets('keeps the flat PolygonLayer when extrude is false', (
      tester,
    ) async {
      final query = await openQuery(tester);
      final controller = GeoSelectionController()..select(feature);

      await tester.pumpWidget(buildMap(query, controller, extrude: false));

      expect(find.byType(PolygonLayer), findsOneWidget);
      expect(find.byWidgetPredicate(isExtrusionPaint), findsNothing);
    });
  });
}
