## 1.0.0

* Initial release of `dart_geoquery_flutter`.
* `GeoInteractiveLayer` for reactive vector spatial querying and highlight rendering on `flutter_map`.
* `GeoSelectionController` for managing active feature selections with custom styles and support for both single-selection (`multiSelect: false`) and multi-selection (`multiSelect: true`) modes.
* Zero base-map re-renders: only selected features are drawn on an overlay `PolygonLayer`.
* Integrated tap debouncing to avoid redundant queries during rapid interactions.
* Support for Sutherland-Hodgman cross-tile boundary stitching and seamless coordinate bridging between `dart_geoquery` and `latlong2`.
