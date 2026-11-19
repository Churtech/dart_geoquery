# dart_geoquery

A fast, serverless, mapless offline geospatial query engine for **PMTiles** (and Mapbox Vector Tiles) in pure Dart.

Query vector map data directly from `.pmtiles` files with **zero UI dependencies**, **no platform views**, **no server**, and **100% offline**.

---

## 🚀 Why dart_geoquery?

In Flutter and Dart, map libraries (`google_maps_flutter`, `mapbox_maps_flutter`, `flutter_map`) focus exclusively on **rendering pixels onto the screen**. If you want to answer questions like:
- *"Which delivery neighborhood or district is the user currently located in?"*
- *"Which property lot or building polygon was selected?"*
- *"What points of interest are within 500 meters without making an API call?"*

...you were previously forced to either keep a map widget active, load multi-megabyte GeoJSON files into RAM, or maintain an external GIS backend.

**`dart_geoquery` treats PMTiles files as an embedded, queryable spatial database.**

---

## ✨ Features

- **Pure Dart**: Zero Flutter or C++ dependencies. Runs anywhere Dart runs (Flutter, background Isolates, Dart CLI, or backend servers).
- **$O(1)$ Direct Tile Seeking**: Uses Web Mercator projection arithmetic and Hilbert curve indexing to jump directly to the exact tile bytes without loading the archive into memory.
- **Fast Point-in-Polygon (PIP)**: Accurate Jordan curve ray-casting in local tile space with automatic axis-aligned bounding box fast rejection and interior hole handling.
- **Multi-Polygon Support**: Transparently evaluates complex multi-polygon geometries.
- **Attribute Access**: Extract strongly typed feature attributes (`feature['name']`, `feature.get<double>('area')`).
- **Spatial Proximity Searches**: Query points and polygons within a radius via `geo.within(center, radiusMeters: 500)`.

---

## 📦 Installation

Add `dart_geoquery` to your `pubspec.yaml`:

```yaml
dependencies:
  dart_geoquery: ^1.0.0
```

---

## 💡 Quick Start

```dart
import 'package:dart_geoquery/dart_geoquery.dart';

void main() async {
  // Open local file or remote URL
  final geo = await GeoQuery.open('assets/zones.pmtiles');

  final userLocation = LatLng(4.65, -74.05);

  // 1. Point-in-polygon: Which zone is the user currently in?
  final zone = await geo.at(userLocation, layer: 'barrios');
  if (zone != null) {
    print('Zone: ${zone['nombre']} (ID: ${zone.id})');
  }

  // 2. Spatial proximity: All features within 500 meters
  final nearby = await geo.within(
    userLocation,
    radiusMeters: 500,
    layer: 'tiendas',
  );
  print('Found ${nearby.length} nearby locations.');

  // 3. Attribute filtering
  final largeLots = await geo.where(
    'lotes',
    (feature) => (feature.get<num>('area') ?? 0) > 1000,
  );
  print('Large lots: ${largeLots.length}');
}
```

---

## ⚡ Performance & Benchmarks

Because MVT decoding, geometry unpacking, and Point-In-Polygon math are offloaded to a **long-lived background worker Isolate** with an internal **LRU tile cache** and **pre-computed BBox indexing**, UI jank is completely eliminated:

| Query Type | Latency | What happens under the hood |
|---|---|---|
| **Cold Query** | **~300 - 500 ms** | HTTP Range request for tile bytes + Isolate Protobuf decode + BBox index + PIP |
| **Warm Query** | **0.3 - 0.8 ms (365 µs)** | **Isolate in-memory LRU cache hit** + $O(1)$ BBox rejection + ray casting |

> **Result:** Subsequent queries in the same region run in **sub-millisecond time (~700x faster)** without touching the network or decoding protobuf buffers again.

---

## 🧪 Architecture

```
dart_geoquery
├── lib/
│   ├── dart_geoquery.dart          # Public API facade
│   └── src/
│       ├── geo_query.dart          # Primary GeoQuery engine
│       ├── models/
│       │   ├── geo_feature.dart    # Typed vector feature representation
│       │   └── lat_lng.dart        # WGS84 coordinates & Haversine distance
│       └── spatial/
│           ├── point_in_polygon.dart # Ray-casting + BBox fast rejection + holes
│           └── tile_math.dart        # Web Mercator projection & extent math
└── test/
    └── dart_geoquery_test.dart     # Comprehensive test suite
```

---

## 📄 License

MIT
