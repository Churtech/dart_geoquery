## 1.2.0

* Web support: the library no longer imports `dart:isolate` unconditionally. The background worker is created through a conditional import; on web `useIsolate` is ignored and queries run on the main thread with the same LRU tile cache. The package now supports all six platforms.
* Boundary stitching (`stitchFeature`, `at(..., stitchBoundaries: true)`) now also works without an isolate (web and `useIsolate: false`). Previously the in-process path neither flagged boundary features nor fetched neighbor tiles.
* Internal: tile decoding and matching moved into a platform-neutral `TileQueryEngine` shared by the isolate worker and the in-process path, so both return identical results (including tile-edge clipping of projected rings).
* Added the full MIT license text.

## 1.1.0

* Added `GeoFeature.tileCount`: the number of tiles whose geometry contributed to the feature. It defaults to `1` and `stitchFeature` (and `at(..., stitchBoundaries: true)`) sets it to the source tile plus every neighboring tile that returned matching parts, so callers can tell whether a feature was joined from several tile pieces. `touchesTileBoundary` keeps its existing meaning.

## 1.0.1

* Fixed isolate tile cache desync: after the worker's LRU cache evicted a tile, later queries on that tile silently returned no results. The worker now reports a cache miss and `GeoQuery` reloads the tile bytes and retries once.
* `stitchFeature` no longer throws when a neighboring tile does not exist in the archive.

## 1.0.0

* Initial release of `dart_geoquery`.
* Pure Dart serverless geospatial query engine for PMTiles (v3) archives.
* Fast Jordan curve point-in-polygon (PIP) ray casting in local tile space with bounding box fast-rejection.
* Accurate Sutherland-Hodgman polygon clipping and cross-tile boundary stitching.
* On-demand projection of matching parts within complex `MultiPolygon` geometries.
* Long-lived background Isolate query worker (`useIsolate: true`) for non-blocking asynchronous execution.
* In-memory LRU tile caching to eliminate duplicate tile decompression.
* Support for local PMTiles files and remote URL range requests.
