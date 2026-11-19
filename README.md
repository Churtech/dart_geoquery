# dart_geoquery monorepo

Pub Workspace containing:
- [`packages/dart_geoquery`](packages/dart_geoquery): Pure Dart offline geospatial query engine for PMTiles.
- [`packages/dart_geoquery_flutter`](packages/dart_geoquery_flutter): Interactive selection and highlighting layer for `flutter_map`.

## Workspace Structure

```
dart_geoquery/
├── pubspec.yaml                 # Root Dart workspace manifest
└── packages/
    ├── dart_geoquery/           # Core pure Dart engine
    └── dart_geoquery_flutter/   # flutter_map interactive adapter
```

## Running Tests

```bash
# Run core pure Dart tests
dart test packages/dart_geoquery/test

# Run Flutter map adapter tests
flutter test packages/dart_geoquery_flutter/test
```
