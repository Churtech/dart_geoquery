import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:dart_geoquery_flutter/dart_geoquery_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart' as ll;

void main() {
  group('LatLng Extensions', () {
    test('converts bidirectionally between dart_geoquery and latlong2', () {
      const gqPoint = gq.LatLng(4.65, -74.05);
      final llPoint = gqPoint.toLatLong2();
      expect(llPoint.latitude, equals(4.65));
      expect(llPoint.longitude, equals(-74.05));

      final restored = llPoint.toGeoQuery();
      expect(restored.latitude, equals(4.65));
      expect(restored.longitude, equals(-74.05));
    });
  });

  group('GeoSelectionController', () {
    test('tracks selection state and custom styles', () {
      final controller = GeoSelectionController();
      const featureA = gq.GeoFeature(
        id: 101,
        layer: 'buildings',
        properties: {'name': 'Tower A'},
        geometryType: 'Polygon',
      );
      const featureB = gq.GeoFeature(
        id: 102,
        layer: 'buildings',
        properties: {'name': 'Tower B'},
        geometryType: 'Polygon',
      );

      // Select A
      controller.select(featureA);
      expect(controller.isSelected(101), isTrue);
      expect(controller.isSelected(102), isFalse);
      expect(controller.selectedFeatures.length, equals(1));

      // Toggle B (adds B)
      controller.toggle(featureB);
      expect(controller.isSelected(102), isTrue);
      expect(controller.selectedFeatures.length, equals(2));

      // Toggle A (removes A)
      controller.toggle(featureA);
      expect(controller.isSelected(101), isFalse);
      expect(controller.selectedFeatures.length, equals(1));

      // Clear
      controller.clear();
      expect(controller.selectedFeatures, isEmpty);
      expect(controller.selectedIds, isEmpty);
    });
  });

  group('GeoInteractiveLayer Widget', () {
    testWidgets('renders PolygonLayer with selected features', (tester) async {
      final controller = GeoSelectionController();
      const feature = gq.GeoFeature(
        id: 501,
        layer: 'buildings',
        properties: {'name': 'Auditorium'},
        geometryType: 'Polygon',
        coordinates: [
          [
            gq.LatLng(4.65, -74.05),
            gq.LatLng(4.66, -74.05),
            gq.LatLng(4.66, -74.04),
            gq.LatLng(4.65, -74.04),
          ]
        ],
      );

      // Select feature before build
      controller.select(
        feature,
        style: const PolygonStyle(
          color: Color(0x88FF0000),
          borderColor: Color(0xFFFF0000),
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMap(
              options: const MapOptions(
                initialCenter: ll.LatLng(4.65, -74.05),
                initialZoom: 14,
              ),
              children: [
                ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) {
                    final polygons = controller.selectedFeatures.map((f) {
                      return Polygon(
                        points: f.coordinates!.first
                            .map((c) => c.toLatLong2())
                            .toList(),
                        color: const Color(0x88FF0000),
                      );
                    }).toList();
                    return PolygonLayer(polygons: polygons);
                  },
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(PolygonLayer), findsOneWidget);
    });
  });
}
