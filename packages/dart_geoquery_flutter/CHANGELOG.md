## 1.1.1

* Added the full MIT license text.

## 1.1.0

* Added opt-in 2.5D extrusion to `GeoInteractiveLayer`: `extrude` (default `false`), `heightKey` (default `'height'`), `defaultHeightMeters` (default `10`) and `extrusionPerspective` (default `0.7`). Selected features are drawn in screen space with a roof shifted up by the feature height, walls painted back to front with directional shading, and even-odd roofs that keep holes open. Roof and wall colors are derived from the feature's `PolygonStyle`. The flat `PolygonLayer` path is unchanged when `extrude` is `false`.
* Requires `dart_geoquery: ^1.1.0`.

## 1.0.0

* Initial release of `dart_geoquery_flutter`.
* `GeoInteractiveLayer` for reactive vector spatial querying and highlight rendering on `flutter_map`.
* `GeoSelectionController` for managing active feature selections with custom styles and support for both single-selection (`multiSelect: false`) and multi-selection (`multiSelect: true`) modes.
* Zero base-map re-renders: only selected features are drawn on an overlay `PolygonLayer`.
* Integrated tap debouncing to avoid redundant queries during rapid interactions.
* Support for Sutherland-Hodgman cross-tile boundary stitching and seamless coordinate bridging between `dart_geoquery` and `latlong2`.
