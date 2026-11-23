# Changelog

All notable changes to the `dart_geoquery` workspace will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Changed

- Re-recorded the README demo GIF (`doc/demo.gif`) on Android to show the 2.5D building extrusion, the new feature panel and the shaded globe. It is now ~650 KB instead of ~5.4 MB.

## [1.1.0] - 2026-11-23

### Added

#### `dart_geoquery` (v1.1.0)
- `GeoFeature.tileCount`: number of tiles whose geometry contributed to a feature. It is `1` for single-tile features; `stitchFeature` / `at(..., stitchBoundaries: true)` set it to the source tile plus every neighboring tile that returned matching parts. `touchesTileBoundary` keeps its meaning.

#### `dart_geoquery_flutter` (v1.1.0)
- Opt-in 2.5D extrusion in `GeoInteractiveLayer` (`extrude`, `heightKey`, `defaultHeightMeters`, `extrusionPerspective`). Selected features rise by their height in screen space, with back-to-front shaded walls, an even-odd roof that keeps holes open, and colors derived from `PolygonStyle`.

### Changed

#### `dart_geoquery_flutter` (v1.1.0)
- Requires `dart_geoquery: ^1.1.0`.

#### Example app
- Selected buildings are extruded using their `height` property.
- Low-zoom globe gains sphere lighting (top-left highlight, limb darkening along the real clipped edge) and an atmosphere rim glow that follow the globe shape at every zoom; the overlays ignore pointer events. Only the map content is tilted (scaled to cover the clip), so the globe silhouette stays round.
- Feature panel uses plain wording: "Shape: complete / joined from N parts" (from `tileCount`), "Show grid", "Show all data", "Show a building across zones" and "Response: X ms".
- Panel title shows a readable building type instead of the raw `kind`; the `sort_rank` chip was removed (still listed under "Show all data").
- Area is now the primary metric; height, approximate floors (height / 3) and perimeter chips are shown when data exists. Area sums all rings so holes subtract and stitched pieces add up.

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
