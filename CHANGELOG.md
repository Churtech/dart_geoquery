# Changelog

All notable changes to the `dart_geoquery` workspace will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.1] - 2026-11-23

### Fixed

#### `dart_geoquery` (v1.0.1)
- Isolate tile cache desync: once the worker's LRU cache evicted a tile, queries on that tile silently returned no results. The worker now reports a cache miss and the tile bytes are reloaded and resent.
- `stitchFeature` no longer throws when a neighboring tile is missing from the archive.

## [1.0.0] - 2026-11-19

### Added

#### `dart_geoquery` (v1.0.0)
- Pure Dart spatial query engine for PMTiles (v3) archives with zero UI dependencies.
- $O(1)$ direct tile byte seeking via Web Mercator Hilbert curve arithmetic.
- Point-in-polygon (PIP) Jordan curve ray casting with AABB bounding-box fast rejection.
- Sutherland-Hodgman cross-tile polygon clipping and boundary stitching across arbitrary tile seams.
- On-demand projection of matched components in complex `MultiPolygon` collections.
- Background isolate query worker (`useIsolate: true`) to offload tile decoding and ray casting from the main thread.
- Thread-safe in-memory LRU tile caching.

#### `dart_geoquery_flutter` (v1.0.0)
- `GeoInteractiveLayer` widget for `flutter_map` (v8+).
- `GeoSelectionController` for managing active feature selections, custom polygon styles, and single/multi-selection modes.
- Automatic deselect on background/empty tap.
- Bidirectional coordinate conversion between `dart_geoquery.LatLng` and `latlong2.LatLng`.
- Interactive example app supporting offline Bogota and Wellington PMTiles datasets, custom styling, metrics inspection, and location tracking.
