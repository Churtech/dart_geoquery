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
