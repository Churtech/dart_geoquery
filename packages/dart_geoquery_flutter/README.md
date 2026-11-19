# dart_geoquery_flutter

Interactive vector feature selection, spatial querying, and reactive highlighting for **`flutter_map`**, powered by the **`dart_geoquery`** engine.

---

## 🌟 Features

- **Tap-and-Query Vector Polygons**: Turn any static PMTiles vector map into an interactive, clickable surface without loading GeoJSON files or running an external GIS server.
- **Sub-millisecond Warm Hits**: Vector decoding and point-in-polygon queries execute on a long-lived background isolate with an in-memory LRU cache.
- **Cross-Tile Geometry Stitching**: Polygons spanning across tile boundaries (including diagonals) are automatically stitched and clipped cleanly.
- **Zero Base Map Re-renders**: Renders only the active selection highlight using `PolygonLayer`, leaving your base map tiles completely undisturbed.
- **Debounced Taps**: Built-in debounce mechanism prevents race conditions on rapid taps.

---

## 📦 Installation

Add `dart_geoquery_flutter` and `flutter_map` to your `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_map: ^8.0.0
  dart_geoquery_flutter: ^1.0.0
```

---

## 💡 Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:dart_geoquery_flutter/dart_geoquery_flutter.dart';

class InteractiveMapScreen extends StatefulWidget {
  const InteractiveMapScreen({super.key});

  @override
  State<InteractiveMapScreen> createState() => _InteractiveMapScreenState();
}

class _InteractiveMapScreenState extends State<InteractiveMapScreen> {
  final GlobalKey<GeoInteractiveLayerState> _interactiveKey = GlobalKey();
  final GeoSelectionController _selectionController = GeoSelectionController();
  gq.GeoQuery? _geoQuery;

  @override
  void initState() {
    super.initState();
    _initGeo();
  }

  Future<void> _initGeo() async {
    final query = await gq.GeoQuery.open(
      'https://r2-public.protomaps.com/protomaps-sample-datasets/nz-buildings-v3.pmtiles',
    );
    setState(() => _geoQuery = query);
  }

  @override
  void dispose() {
    _geoQuery?.close();
    _selectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_geoQuery == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Interactive Vector Map')),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: const LatLng(-41.2775, 174.7701), // Wellington, NZ
          initialZoom: 15,
          onTap: (_, point) {
            _interactiveKey.currentState?.handleTap(point);
          },
        ),
        children: [
          // 1. Your standard base map tile layer (e.g. OpenStreetMap, Protomaps, etc.)
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          ),

          // 2. Interactive Selection Layer
          GeoInteractiveLayer(
            key: _interactiveKey,
            query: _geoQuery!,
            layer: 'buildings',
            idKey: 'building_i',
            controller: _selectionController,
            selectedStyle: (feature) => PolygonStyle(
              color: Colors.teal.withOpacity(0.4),
              borderColor: Colors.teal,
              borderStrokeWidth: 2.5,
              label: feature['town_city'],
            ),
            onFeatureTap: (feature) {
              if (feature != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Selected: ${feature['town_city']} (ID: ${feature['building_i']})'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
```

---

## 📄 License

MIT
