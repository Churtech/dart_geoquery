import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/vector_tile.dart';

import 'models/geo_feature.dart';
import 'models/lat_lng.dart';
import 'spatial/point_in_polygon.dart';
import 'spatial/tile_math.dart';

/// Geospatial query engine for PMTiles without UI, rendering, or network requirements.
class GeoQuery {
  final PmTilesArchive _archive;
  final Map<String, dynamic>? _metadata;
  final Map<String, (int minZoom, int maxZoom)> _layerZoomRanges;

  GeoQuery._(
    this._archive, {
    this._metadata,
    this._layerZoomRanges = const {},
  });

  /// Opens a local PMTiles file or remote URL.
  static Future<GeoQuery> open(String pathOrUrl) async {
    final archive = await PmTilesArchive.from(pathOrUrl);
    return fromArchive(archive);
  }

  /// Creates a [GeoQuery] instance from in-memory PMTiles bytes.
  static Future<GeoQuery> fromBytes(Uint8List bytes) async {
    final archive = await PmTilesArchive.fromBytes(bytes);
    return fromArchive(archive);
  }

  /// Creates a [GeoQuery] instance from an existing [PmTilesArchive].
  static Future<GeoQuery> fromArchive(PmTilesArchive archive) async {
    Map<String, dynamic>? meta;
    final layerZoomRanges = <String, (int minZoom, int maxZoom)>{};

    try {
      final rawMeta = await archive.metadata;
      if (rawMeta is Map<String, dynamic>) {
        meta = rawMeta;
      } else if (rawMeta is Map) {
        meta = rawMeta.cast<String, dynamic>();
      }

      // Parse vector_layers if present in metadata
      if (meta != null && meta['vector_layers'] is List) {
        final layersList = meta['vector_layers'] as List;
        for (final item in layersList) {
          if (item is Map) {
            final id = item['id']?.toString();
            final minz = (item['minzoom'] as num?)?.toInt() ?? archive.header.minZoom;
            final maxz = (item['maxzoom'] as num?)?.toInt() ?? archive.header.maxZoom;
            if (id != null) {
              layerZoomRanges[id] = (minz, maxz);
            }
          }
        }
      }
    } catch (_) {
      // Metadata read error is non-fatal; falls back to archive header zooms
    }

    return GeoQuery._(
      archive,
      metadata: meta,
      layerZoomRanges: layerZoomRanges,
    );
  }

  /// Archive minimum zoom level.
  int get minZoom => _archive.header.minZoom;

  /// Archive maximum zoom level.
  int get maxZoom => _archive.header.maxZoom;

  /// Embedded metadata JSON, if present.
  Map<String, dynamic>? get metadata => _metadata;

  /// Known vector layers found in metadata.
  List<String> get layers => _layerZoomRanges.keys.toList();

  /// Resolves the optimal zoom level for querying a specific [layer].
  int resolveZoomForLayer(String? layer, int? requestedZoom) {
    if (requestedZoom != null) return requestedZoom;
    if (layer != null && _layerZoomRanges.containsKey(layer)) {
      return _layerZoomRanges[layer]!.$2;
    }
    return maxZoom;
  }

  /// Finds the first feature containing [point] via Point-in-Polygon.
  ///
  /// Optionally filter by [layer] name or specify [zoom] level.
  /// Returns `null` if no polygon contains the point.
  Future<GeoFeature?> at(
    LatLng point, {
    String? layer,
    int? zoom,
  }) async {
    final results = await allAt(point, layer: layer, zoom: zoom);
    return results.isNotEmpty ? results.first : null;
  }

  /// Finds all features containing [point] via Point-in-Polygon.
  ///
  /// Useful when layers overlap or multiple polygon features match the point.
  Future<List<GeoFeature>> allAt(
    LatLng point, {
    String? layer,
    int? zoom,
  }) async {
    final targetZoom = resolveZoomForLayer(layer, zoom);
    final (tileX, tileY) = TileMath.latLngToTile(point, targetZoom);
    final tileId = ZXY(targetZoom, tileX, tileY).toTileId();

    final tile = await _archive.tile(tileId);
    final bytes = tile.bytes();
    if (bytes.isEmpty) {
      return const [];
    }

    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final vectorTile = VectorTile.fromBytes(bytes: uint8Bytes);
    final matchingFeatures = <GeoFeature>[];

    for (final vLayer in vectorTile.layers) {
      if (layer != null && vLayer.name != layer) {
        continue;
      }

      final (localX, localY) = TileMath.latLngToTileCoordinates(
        point: point,
        zoom: targetZoom,
        extent: vLayer.extent,
      );

      for (final feature in vLayer.features) {
        if (feature.type != VectorTileGeomType.POLYGON) {
          continue;
        }

        feature.decodeGeometry();
        final isInside = _testFeatureContainsPoint(feature, localX, localY);

        if (isInside) {
          matchingFeatures.add(_toGeoFeature(feature, vLayer.name));
        }
      }
    }

    return matchingFeatures;
  }

  /// Finds all features within [radiusMeters] of [center].
  ///
  /// Works for points, linestrings, and polygons.
  Future<List<GeoFeature>> within(
    LatLng center, {
    required double radiusMeters,
    String? layer,
    int? zoom,
  }) async {
    final targetZoom = resolveZoomForLayer(layer, zoom);
    final (tileX, tileY) = TileMath.latLngToTile(center, targetZoom);
    final tileId = ZXY(targetZoom, tileX, tileY).toTileId();

    final tile = await _archive.tile(tileId);
    final bytes = tile.bytes();
    if (bytes.isEmpty) {
      return const [];
    }

    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final vectorTile = VectorTile.fromBytes(bytes: uint8Bytes);
    final matchingFeatures = <GeoFeature>[];

    for (final vLayer in vectorTile.layers) {
      if (layer != null && vLayer.name != layer) {
        continue;
      }

      for (final feature in vLayer.features) {
        feature.decodeGeometry();
        final geom = feature.geometry;

        if (geom is GeometryPoint) {
          final latLng = TileMath.tileCoordinatesToLatLng(
            tileX: tileX,
            tileY: tileY,
            zoom: targetZoom,
            localX: geom.coordinates[0],
            localY: geom.coordinates[1],
            extent: vLayer.extent,
          );
          if (center.distanceTo(latLng) <= radiusMeters) {
            matchingFeatures.add(_toGeoFeature(feature, vLayer.name));
          }
        } else if (geom is GeometryPolygon || geom is GeometryMultiPolygon) {
          final (localX, localY) = TileMath.latLngToTileCoordinates(
            point: center,
            zoom: targetZoom,
            extent: vLayer.extent,
          );
          if (_testFeatureContainsPoint(feature, localX, localY)) {
            matchingFeatures.add(_toGeoFeature(feature, vLayer.name));
          }
        }
      }
    }

    return matchingFeatures;
  }

  /// Filters features in [layer] matching the custom [predicate].
  Future<List<GeoFeature>> where(
    String layer,
    bool Function(GeoFeature feature) predicate, {
    int? zoom,
  }) async {
    final targetZoom = resolveZoomForLayer(layer, zoom);
    final matchingFeatures = <GeoFeature>[];

    for (final entry in _archive.root.entries) {
      final zxy = ZXY.fromTileId(entry.tileId);
      if (zxy.z != targetZoom) continue;

      final tile = await _archive.tile(entry.tileId);
      final bytes = tile.bytes();
      if (bytes.isEmpty) continue;

      final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
      final vectorTile = VectorTile.fromBytes(bytes: uint8Bytes);
      for (final vLayer in vectorTile.layers) {
        if (vLayer.name != layer) continue;

        for (final feature in vLayer.features) {
          final geoFeature = _toGeoFeature(feature, vLayer.name);
          if (predicate(geoFeature)) {
            matchingFeatures.add(geoFeature);
          }
        }
      }
    }

    return matchingFeatures;
  }

  bool _testFeatureContainsPoint(
    VectorTileFeature feature,
    double localX,
    double localY,
  ) {
    final geom = feature.geometry;
    if (geom is GeometryPolygon) {
      final coords = geom.coordinates;
      return PointInPolygon.containsPoint(
        px: localX,
        py: localY,
        rings: coords,
      );
    } else if (geom is GeometryMultiPolygon) {
      final coords = geom.coordinates;
      if (coords == null) return false;
      return PointInPolygon.containsPointInMultiPolygon(
        px: localX,
        py: localY,
        multiPolygon: coords,
      );
    }
    return false;
  }

  GeoFeature _toGeoFeature(VectorTileFeature feature, String layerName) {
    feature.decodeProperties();
    final rawProps = feature.properties ?? const {};
    final props = <String, dynamic>{};

    rawProps.forEach((key, val) {
      final v = val.value;
      if (v is Int64) {
        props[key] = v.toInt();
      } else {
        props[key] = v;
      }
    });

    final id = feature.id != Int64.ZERO ? feature.id.toInt() : null;

    return GeoFeature(
      id: id,
      layer: layerName,
      properties: props,
      geometryType: feature.geometryType?.name ?? 'Unknown',
    );
  }
}
