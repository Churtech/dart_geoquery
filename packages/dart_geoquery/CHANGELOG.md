## 1.0.0

* Initial release of `dart_geoquery`.
* Pure Dart serverless geospatial query engine for PMTiles (v3) archives.
* Fast Jordan curve point-in-polygon (PIP) ray casting in local tile space with bounding box fast-rejection.
* Accurate Sutherland-Hodgman polygon clipping and cross-tile boundary stitching.
* On-demand projection of matching parts within complex `MultiPolygon` geometries.
* Long-lived background Isolate query worker (`useIsolate: true`) for non-blocking asynchronous execution.
* In-memory LRU tile caching to eliminate duplicate tile decompression.
* Support for local PMTiles files and remote URL range requests.
