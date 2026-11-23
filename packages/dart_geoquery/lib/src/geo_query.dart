import 'dart:async';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:pmtiles/pmtiles.dart';
import 'package:vector_tile/vector_tile.dart';

import 'isolate/isolate_query_worker.dart';
import 'isolate/query_message.dart';
import 'models/geo_feature.dart';
import 'models/lat_lng.dart';
import 'spatial/point_in_polygon.dart';
import 'spatial/tile_math.dart';

/// Geospatial query engine for PMTiles without UI, rendering, or network requirements.
class GeoQuery {
  final PmTilesArchive _archive;
  final Map<String, dynamic>? _metadata;
  final Map<String, (int minZoom, int maxZoom)> _layerZoomRanges;
  final IsolateQueryWorker? _worker;
  final Set<int> _workerCachedTileIds = <int>{};

  GeoQuery._(
    this._archive, {
    this._metadata,
    this._layerZoomRanges = const {},
    this._worker,
  });

  /// Opens a local PMTiles file or remote URL.
  ///
  /// [useIsolate] offloads MVT decoding and spatial operations to a dedicated
  /// background worker isolate, keeping the UI/main thread completely free.
  /// [cacheCapacity] defines the number of decoded tiles to keep in the isolate's LRU cache.
  static Future<GeoQuery> open(
    String pathOrUrl, {
    bool useIsolate = true,
    int cacheCapacity = 64,
  }) async {
    final archive = await PmTilesArchive.from(pathOrUrl);
    return fromArchive(
      archive,
      useIsolate: useIsolate,
      cacheCapacity: cacheCapacity,
    );
  }

  /// Creates a [GeoQuery] instance from in-memory PMTiles bytes.
  static Future<GeoQuery> fromBytes(
    Uint8List bytes, {
    bool useIsolate = true,
    int cacheCapacity = 64,
  }) async {
    final archive = await PmTilesArchive.fromBytes(bytes);
    return fromArchive(
      archive,
      useIsolate: useIsolate,
      cacheCapacity: cacheCapacity,
    );
  }

  /// Creates a [GeoQuery] instance from an existing [PmTilesArchive].
  static Future<GeoQuery> fromArchive(
    PmTilesArchive archive, {
    bool useIsolate = true,
    int cacheCapacity = 64,
  }) async {
    Map<String, dynamic>? meta;
    final layerZoomRanges = <String, (int minZoom, int maxZoom)>{};

    try {
      final rawMeta = await archive.metadata;
      if (rawMeta is Map<String, dynamic>) {
        meta = rawMeta;
      } else if (rawMeta is Map) {
        meta = rawMeta.cast<String, dynamic>();
      }

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
      // Non-fatal; falls back to archive header zooms
    }

    IsolateQueryWorker? worker;
    if (useIsolate) {
      worker = await IsolateQueryWorker.spawn(cacheCapacity: cacheCapacity);
    }

    return GeoQuery._(
      archive,
      metadata: meta,
      layerZoomRanges: layerZoomRanges,
      worker: worker,
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
    if (requestedZoom != null) return requestedZoom.clamp(minZoom, maxZoom);
    if (layer != null && _layerZoomRanges.containsKey(layer)) {
      return _layerZoomRanges[layer]!.$2.clamp(minZoom, maxZoom);
    }
    return maxZoom;
  }

  /// Finds the first feature containing [point] via Point-in-Polygon.
  ///
  /// If [stitchBoundaries] is true and the feature intersects the tile edge,
  /// neighboring tiles are checked by [idKey] to stitch boundary parts into
  /// a continuous geometry.
  Future<GeoFeature?> at(
    LatLng point, {
    String? layer,
    int? zoom,
    bool stitchBoundaries = false,
    String idKey = 'id',
    int maxStitchDepth = 4,
  }) async {
    final results = await allAt(point, layer: layer, zoom: zoom);
    if (results.isEmpty) return null;

    final first = results.first;
    if (stitchBoundaries && first.touchesTileBoundary) {
      return stitchFeature(first, idKey: idKey, maxDepth: maxStitchDepth);
    }

    return first;
  }

  /// Finds all features containing [point] via Point-in-Polygon.
  Future<List<GeoFeature>> allAt(
    LatLng point, {
    String? layer,
    int? zoom,
  }) async {
    final targetZoom = resolveZoomForLayer(layer, zoom);
    final (tileX, tileY) = TileMath.latLngToTile(point, targetZoom);
    final tileId = ZXY(targetZoom, tileX, tileY).toTileId();

    const defaultExtent = 4096;
    final (localX, localY) = TileMath.latLngToTileCoordinates(
      point: point,
      zoom: targetZoom,
      extent: defaultExtent,
    );

    // If long-lived isolate worker is enabled, offload decoding & PIP
    if (_worker != null) {
      final worker = _worker;
      late final List<GeoFeatureDto> dtos;
      try {
        dtos = await _runOnWorker(
          tileId,
          (tileBytes) => worker.queryPoint(
            tileId: tileId,
            tileX: tileX,
            tileY: tileY,
            zoom: targetZoom,
            localX: localX,
            localY: localY,
            layer: layer,
            tileBytes: tileBytes,
          ),
        );
      } catch (_) {
        return const [];
      }

      return dtos.map((d) {
        final rings = d.coordinates
            ?.map((r) => r.map((c) => LatLng(c.$1, c.$2)).toList())
            .toList();

        final multiRings = d.multiCoordinates
            ?.map((part) =>
                part.map((r) => r.map((c) => LatLng(c.$1, c.$2)).toList()).toList())
            .toList();

        return GeoFeature(
          id: d.id,
          layer: d.layer,
          properties: d.properties,
          geometryType: d.geometryType,
          coordinates: rings,
          multiCoordinates: multiRings,
          touchesTileBoundary: d.touchesTileBoundary,
          candidateNeighborOffsets: d.candidateNeighborOffsets,
          sourceTile: d.sourceTile,
        );
      }).toList();
    }

    // Direct synchronous fallback (without isolate)
    late final List<int> bytes;
    try {
      final tile = await _archive.tile(tileId);
      bytes = tile.bytes();
      if (bytes.isEmpty) return const [];
    } on TileNotFoundException {
      return const [];
    } catch (_) {
      return const [];
    }

    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final vectorTile = VectorTile.fromBytes(bytes: uint8Bytes);
    final matchingFeatures = <GeoFeature>[];

    for (final vLayer in vectorTile.layers) {
      if (layer != null && vLayer.name != layer) continue;

      final (layerLocalX, layerLocalY) = vLayer.extent == defaultExtent
          ? (localX, localY)
          : TileMath.latLngToTileCoordinates(
              point: point,
              zoom: targetZoom,
              extent: vLayer.extent,
            );

      for (final feature in vLayer.features) {
        if (feature.type != VectorTileGeomType.POLYGON) continue;

        feature.decodeGeometry();
        final geom = feature.geometry;
        if (geom == null) continue;

        List<List<LatLng>>? matchedRings;
        if (geom is GeometryPolygon) {
          final isInside = PointInPolygon.containsPoint(
            px: layerLocalX,
            py: layerLocalY,
            rings: geom.coordinates,
          );
          if (isInside) {
            matchedRings = geom.coordinates
                .map((r) => r
                    .map((pt) => TileMath.tileCoordinatesToLatLng(
                          tileX: tileX,
                          tileY: tileY,
                          zoom: targetZoom,
                          localX: pt[0],
                          localY: pt[1],
                          extent: vLayer.extent,
                        ))
                    .toList())
                .toList();
          }
        } else if (geom is GeometryMultiPolygon && geom.coordinates != null) {
          for (final poly in geom.coordinates!) {
            final isInside = PointInPolygon.containsPoint(
              px: layerLocalX,
              py: layerLocalY,
              rings: poly,
            );
            if (isInside) {
              matchedRings = poly
                  .map((r) => r
                      .map((pt) => TileMath.tileCoordinatesToLatLng(
                            tileX: tileX,
                            tileY: tileY,
                            zoom: targetZoom,
                            localX: pt[0],
                            localY: pt[1],
                            extent: vLayer.extent,
                          ))
                      .toList())
                  .toList();
              break;
            }
          }
        }

        if (matchedRings != null) {
          matchingFeatures.add(_toGeoFeature(
            feature,
            vLayer.name,
            tileX,
            tileY,
            targetZoom,
            vLayer.extent,
            coordinates: matchedRings,
          ));
        }
      }
    }

    return matchingFeatures;
  }

  /// Stitches geometries across tile borders by querying only the candidate
  /// neighboring tiles matching the touched edge directions and sharing [idKey].
  Future<GeoFeature> stitchFeature(
    GeoFeature feature, {
    required String idKey,
    int maxDepth = 4,
  }) async {
    final source = feature.sourceTile;
    if (source == null || !feature.touchesTileBoundary) {
      return feature;
    }

    final idValue = idKey == 'id' ? feature.id : feature.properties[idKey];
    if (idValue == null) return feature;

    final (startX, startY, zoom) = source;
    final maxTile = (1 << zoom) - 1;

    final allRings = <List<LatLng>>[
      if (feature.coordinates != null) ...feature.coordinates!,
    ];
    final visitedTiles = <(int x, int y)>{(startX, startY)};
    final queue = <((int x, int y), List<(int dx, int dy)>)>[
      ((startX, startY), feature.candidateNeighborOffsets),
    ];

    while (queue.isNotEmpty && visitedTiles.length < maxDepth) {
      final (currentTile, candidateOffsets) = queue.removeAt(0);

      // Visit ONLY the candidate offsets corresponding to touched edges
      for (final (dx, dy) in candidateOffsets) {
        final nx = currentTile.$1 + dx;
        final ny = currentTile.$2 + dy;

        if (nx < 0 || nx > maxTile || ny < 0 || ny > maxTile) continue;
        if (visitedTiles.contains((nx, ny))) continue;

        visitedTiles.add((nx, ny));
        final neighborTileId = ZXY(zoom, nx, ny).toTileId();

        final worker = _worker;
        if (worker != null) {
          final dtos = await _runOnWorker(
            neighborTileId,
            (tileBytes) => worker.fetchFeatureById(
              tileId: neighborTileId,
              tileX: nx,
              tileY: ny,
              zoom: zoom,
              layer: feature.layer,
              idKey: idKey,
              idValue: idValue,
              tileBytes: tileBytes,
            ),
          );

          for (final dto in dtos) {
            if (dto.coordinates != null) {
              for (final ring in dto.coordinates!) {
                allRings.add(ring.map((c) => LatLng(c.$1, c.$2)).toList());
              }
            }
            if (dto.touchesTileBoundary &&
                visitedTiles.length < maxDepth &&
                dto.candidateNeighborOffsets.isNotEmpty) {
              queue.add(((nx, ny), dto.candidateNeighborOffsets));
            }
          }
        }
      }
    }

    return feature.copyWith(
      coordinates: allRings,
      touchesTileBoundary: false, // Fully stitched
    );
  }

  /// Finds all features within [radiusMeters] of [center].
  Future<List<GeoFeature>> within(
    LatLng center, {
    required double radiusMeters,
    String? layer,
    int? zoom,
  }) async {
    final targetZoom = resolveZoomForLayer(layer, zoom);
    final (tileX, tileY) = TileMath.latLngToTile(center, targetZoom);
    final tileId = ZXY(targetZoom, tileX, tileY).toTileId();

    late final List<int> bytes;
    try {
      final tile = await _archive.tile(tileId);
      bytes = tile.bytes();
      if (bytes.isEmpty) return const [];
    } on TileNotFoundException {
      return const [];
    } catch (_) {
      return const [];
    }

    final uint8Bytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final vectorTile = VectorTile.fromBytes(bytes: uint8Bytes);
    final matchingFeatures = <GeoFeature>[];

    for (final vLayer in vectorTile.layers) {
      if (layer != null && vLayer.name != layer) continue;

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
            matchingFeatures.add(_toGeoFeature(
              feature,
              vLayer.name,
              tileX,
              tileY,
              targetZoom,
              vLayer.extent,
            ));
          }
        } else if (geom is GeometryPolygon || geom is GeometryMultiPolygon) {
          final (localX, localY) = TileMath.latLngToTileCoordinates(
            point: center,
            zoom: targetZoom,
            extent: vLayer.extent,
          );
          if (_testFeatureContainsPoint(feature, localX, localY)) {
            matchingFeatures.add(_toGeoFeature(
              feature,
              vLayer.name,
              tileX,
              tileY,
              targetZoom,
              vLayer.extent,
            ));
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
          final geoFeature = _toGeoFeature(
            feature,
            vLayer.name,
            zxy.x,
            zxy.y,
            targetZoom,
            vLayer.extent,
          );
          if (predicate(geoFeature)) {
            matchingFeatures.add(geoFeature);
          }
        }
      }
    }

    return matchingFeatures;
  }

  /// Closes the background isolate and releases resources.
  void close() {
    _worker?.close();
  }

  /// Sends a request to the worker, attaching tile bytes only when the worker
  /// is not believed to hold the tile. If the worker reports a cache miss
  /// (it evicted the tile from its LRU), the bytes are reloaded and the
  /// request is retried once.
  Future<List<GeoFeatureDto>> _runOnWorker(
    int tileId,
    Future<List<GeoFeatureDto>> Function(Uint8List? tileBytes) send,
  ) async {
    Uint8List? bytes;
    if (!_workerCachedTileIds.contains(tileId)) {
      bytes = await _loadTileBytes(tileId);
      if (bytes == null) return const [];
      _workerCachedTileIds.add(tileId);
    }

    try {
      return await send(bytes);
    } on TileCacheMissException {
      _workerCachedTileIds.remove(tileId);
      final fresh = await _loadTileBytes(tileId);
      if (fresh == null) return const [];
      _workerCachedTileIds.add(tileId);
      return send(fresh);
    }
  }

  /// Loads raw tile bytes, or `null` if the tile is missing or empty.
  Future<Uint8List?> _loadTileBytes(int tileId) async {
    try {
      final tile = await _archive.tile(tileId);
      final raw = tile.bytes();
      if (raw.isEmpty) return null;
      return raw is Uint8List ? raw : Uint8List.fromList(raw);
    } on TileNotFoundException {
      return null;
    }
  }

  bool _testFeatureContainsPoint(
    VectorTileFeature feature,
    double localX,
    double localY,
  ) {
    final geom = feature.geometry;
    if (geom is GeometryPolygon) {
      return PointInPolygon.containsPoint(
        px: localX,
        py: localY,
        rings: geom.coordinates,
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

  GeoFeature _toGeoFeature(
    VectorTileFeature feature,
    String layerName,
    int tileX,
    int tileY,
    int zoom,
    int extent, {
    List<List<LatLng>>? coordinates,
    List<List<List<LatLng>>>? multiCoordinates,
    bool touchesBoundary = false,
    List<(int dx, int dy)> candidateNeighborOffsets = const [],
  }) {
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
      coordinates: coordinates,
      multiCoordinates: multiCoordinates,
      touchesTileBoundary: touchesBoundary,
      candidateNeighborOffsets: candidateNeighborOffsets,
      sourceTile: (tileX, tileY, zoom),
    );
  }
}
