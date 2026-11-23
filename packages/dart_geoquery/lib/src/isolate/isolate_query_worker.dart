import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:vector_tile/vector_tile.dart';

import '../cache/lru_cache.dart';
import '../spatial/point_in_polygon.dart';
import '../spatial/polygon_clipping.dart';
import '../spatial/tile_math.dart';
import 'query_message.dart';

class _CachedTile {
  final int tileId;
  final int tileX;
  final int tileY;
  final int zoom;
  final List<_CachedLayer> layers;

  _CachedTile({
    required this.tileId,
    required this.tileX,
    required this.tileY,
    required this.zoom,
    required this.layers,
  });
}

class _CachedLayer {
  final String name;
  final int extent;
  final List<_CachedFeature> polygonFeatures;

  _CachedLayer({
    required this.name,
    required this.extent,
    required this.polygonFeatures,
  });
}

class _CachedFeature {
  final int? id;
  final Map<String, dynamic> properties;
  final String geometryType;
  final Geometry geometry;
  final List<double> bbox; // [minX, minY, maxX, maxY]
  final bool touchesBoundary;
  final List<(int dx, int dy)> candidateNeighborOffsets;

  _CachedFeature({
    this.id,
    required this.properties,
    required this.geometryType,
    required this.geometry,
    required this.bbox,
    required this.touchesBoundary,
    required this.candidateNeighborOffsets,
  });
}

/// Long-lived background Isolate worker for vector tile decoding and spatial queries.
class IsolateQueryWorker {
  final Isolate _isolate;
  final SendPort _sendPort;
  final ReceivePort _receivePort;
  final Map<int, Completer<List<GeoFeatureDto>>> _pendingRequests = {};
  int _nextRequestId = 1;
  bool _closed = false;

  IsolateQueryWorker._(this._isolate, this._sendPort, this._receivePort) {
    _receivePort.listen((message) {
      if (message is PointQueryResponse) {
        final completer = _pendingRequests.remove(message.requestId);
        if (completer == null) return;
        if (message.cacheMiss) {
          completer.completeError(const TileCacheMissException());
        } else {
          completer.complete(message.features);
        }
      }
    });
  }

  /// Spawns the worker isolate and completes the initial handshake.
  static Future<IsolateQueryWorker> spawn({int cacheCapacity = 64}) async {
    final initPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _isolateEntryPoint,
      [initPort.sendPort, cacheCapacity],
      debugName: 'dart_geoquery_worker',
    );

    final sendPort = await initPort.first as SendPort;
    final messagePort = ReceivePort();
    sendPort.send(messagePort.sendPort);

    return IsolateQueryWorker._(isolate, sendPort, messagePort);
  }

  /// Dispatches a point-in-polygon query to the isolate worker.
  Future<List<GeoFeatureDto>> queryPoint({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required double localX,
    required double localY,
    String? layer,
    Uint8List? tileBytes,
  }) {
    if (_closed) {
      throw StateError('IsolateQueryWorker is closed');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<List<GeoFeatureDto>>();
    _pendingRequests[requestId] = completer;

    _sendPort.send(PointQueryRequest(
      requestId: requestId,
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      tileBytes: tileBytes,
      layer: layer,
      localX: localX,
      localY: localY,
    ));

    return completer.future;
  }

  /// Fetches features by ID in a specific tile (used for neighbor tile boundary stitching).
  Future<List<GeoFeatureDto>> fetchFeatureById({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required String layer,
    required String idKey,
    required dynamic idValue,
    Uint8List? tileBytes,
  }) {
    if (_closed) {
      throw StateError('IsolateQueryWorker is closed');
    }

    final requestId = _nextRequestId++;
    final completer = Completer<List<GeoFeatureDto>>();
    _pendingRequests[requestId] = completer;

    _sendPort.send(FetchFeatureByIdRequest(
      requestId: requestId,
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      tileBytes: tileBytes,
      layer: layer,
      idKey: idKey,
      idValue: idValue,
    ));

    return completer.future;
  }

  /// Terminates the worker isolate.
  void close() {
    if (_closed) return;
    _closed = true;
    _sendPort.send(const TerminateWorkerCommand());
    _receivePort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  /// Entry point for the spawned isolate.
  static void _isolateEntryPoint(List<dynamic> args) {
    final initSendPort = args[0] as SendPort;
    final cacheCapacity = args[1] as int;

    final commandPort = ReceivePort();
    initSendPort.send(commandPort.sendPort);

    SendPort? replyPort;
    final tileCache = LruCache<int, _CachedTile>(capacity: cacheCapacity);

    commandPort.listen((message) {
      if (message is SendPort) {
        replyPort = message;
        return;
      }

      if (message is TerminateWorkerCommand) {
        commandPort.close();
        return;
      }

      if (message is PointQueryRequest) {
        final results = _handlePointQuery(message, tileCache);
        replyPort?.send(PointQueryResponse(
          requestId: message.requestId,
          features: results ?? const [],
          cacheMiss: results == null,
        ));
      } else if (message is FetchFeatureByIdRequest) {
        final results = _handleFetchById(message, tileCache);
        replyPort?.send(PointQueryResponse(
          requestId: message.requestId,
          features: results ?? const [],
          cacheMiss: results == null,
        ));
      }
    });
  }

  static _CachedTile? _ensureTileCached({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required Uint8List? tileBytes,
    required LruCache<int, _CachedTile> cache,
  }) {
    var cached = cache.get(tileId);
    if (cached != null) return cached;

    if (tileBytes == null || tileBytes.isEmpty) return null;

    final vTile = VectorTile.fromBytes(bytes: tileBytes);
    final cachedLayers = <_CachedLayer>[];

    for (final vLayer in vTile.layers) {
      final polygonFeatures = <_CachedFeature>[];

      for (final feat in vLayer.features) {
        if (feat.type != VectorTileGeomType.POLYGON) continue;

        feat.decodeGeometry();
        feat.decodeProperties();

        final geom = feat.geometry;
        if (geom == null) continue;

        final bbox = _calculateBbox(geom);
        final props = _extractProperties(feat.properties);
        final id = feat.id != Int64.ZERO ? feat.id.toInt() : null;

        final extent = vLayer.extent;
        final touchLeft = bbox[0] <= 0.0;
        final touchRight = bbox[2] >= extent.toDouble();
        final touchTop = bbox[1] <= 0.0;
        final touchBottom = bbox[3] >= extent.toDouble();
        final touches = touchLeft || touchRight || touchTop || touchBottom;

        final candidateOffsets = _computeNeighborOffsets(
          touchLeft: touchLeft,
          touchRight: touchRight,
          touchTop: touchTop,
          touchBottom: touchBottom,
        );

        polygonFeatures.add(_CachedFeature(
          id: id,
          properties: props,
          geometryType: feat.geometryType?.name ?? 'Polygon',
          geometry: geom,
          bbox: bbox,
          touchesBoundary: touches,
          candidateNeighborOffsets: candidateOffsets,
        ));
      }

      cachedLayers.add(_CachedLayer(
        name: vLayer.name,
        extent: vLayer.extent,
        polygonFeatures: polygonFeatures,
      ));
    }

    cached = _CachedTile(
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      layers: cachedLayers,
    );
    cache.put(tileId, cached);
    return cached;
  }

  static List<(int dx, int dy)> _computeNeighborOffsets({
    required bool touchLeft,
    required bool touchRight,
    required bool touchTop,
    required bool touchBottom,
  }) {
    final offsets = <(int dx, int dy)>[];
    if (touchLeft) offsets.add((-1, 0));
    if (touchRight) offsets.add((1, 0));
    if (touchTop) offsets.add((0, -1));
    if (touchBottom) offsets.add((0, 1));

    if (touchLeft && touchTop) offsets.add((-1, -1));
    if (touchLeft && touchBottom) offsets.add((-1, 1));
    if (touchRight && touchTop) offsets.add((1, -1));
    if (touchRight && touchBottom) offsets.add((1, 1));

    return offsets;
  }

  /// Returns `null` on a cache miss (tile not held and no bytes supplied).
  static List<GeoFeatureDto>? _handlePointQuery(
    PointQueryRequest req,
    LruCache<int, _CachedTile> cache,
  ) {
    final cached = _ensureTileCached(
      tileId: req.tileId,
      tileX: req.tileX,
      tileY: req.tileY,
      zoom: req.zoom,
      tileBytes: req.tileBytes,
      cache: cache,
    );

    if (cached == null) return req.tileBytes == null ? null : const [];

    final matches = <GeoFeatureDto>[];
    final px = req.localX;
    final py = req.localY;

    for (final layer in cached.layers) {
      if (req.layer != null && layer.name != req.layer) continue;

      for (final feat in layer.polygonFeatures) {
        final bbox = feat.bbox;
        if (px < bbox[0] || px > bbox[2] || py < bbox[1] || py > bbox[3]) {
          continue;
        }

        if (feat.geometry is GeometryPolygon) {
          final isInside = PointInPolygon.containsPoint(
            px: px,
            py: py,
            rings: (feat.geometry as GeometryPolygon).coordinates,
          );
          if (isInside) {
            final projected = _projectPolygonRings(
              (feat.geometry as GeometryPolygon).coordinates,
              cached.tileX,
              cached.tileY,
              cached.zoom,
              layer.extent,
            );
            matches.add(GeoFeatureDto(
              id: feat.id,
              layer: layer.name,
              properties: feat.properties,
              geometryType: feat.geometryType,
              coordinates: projected,
              touchesTileBoundary: feat.touchesBoundary,
              candidateNeighborOffsets: feat.candidateNeighborOffsets,
              sourceTile: (cached.tileX, cached.tileY, cached.zoom),
            ));
          }
        } else if (feat.geometry is GeometryMultiPolygon) {
          final multiCoords =
              (feat.geometry as GeometryMultiPolygon).coordinates;
          if (multiCoords != null) {
            for (int i = 0; i < multiCoords.length; i++) {
              final poly = multiCoords[i];
              final isInside = PointInPolygon.containsPoint(
                px: px,
                py: py,
                rings: poly,
              );
              if (isInside) {
                // Project ONLY this exact matched polygon part on demand
                final projected = _projectPolygonRings(
                  poly,
                  cached.tileX,
                  cached.tileY,
                  cached.zoom,
                  layer.extent,
                );

                // Check if this specific polygon part touches the tile boundary
                final partBbox = _calculatePolygonBbox(poly);
                final extent = layer.extent.toDouble();
                final touchLeft = partBbox[0] <= 0.0;
                final touchRight = partBbox[2] >= extent;
                final touchTop = partBbox[1] <= 0.0;
                final touchBottom = partBbox[3] >= extent;
                final touches =
                    touchLeft || touchRight || touchTop || touchBottom;
                final candidateOffsets = touches
                    ? _computeNeighborOffsets(
                        touchLeft: touchLeft,
                        touchRight: touchRight,
                        touchTop: touchTop,
                        touchBottom: touchBottom,
                      )
                    : const <(int dx, int dy)>[];

                matches.add(GeoFeatureDto(
                  id: feat.id,
                  layer: layer.name,
                  properties: feat.properties,
                  geometryType: feat.geometryType,
                  coordinates: projected,
                  touchesTileBoundary: touches,
                  candidateNeighborOffsets: candidateOffsets,
                  sourceTile: (cached.tileX, cached.tileY, cached.zoom),
                ));
                break;
              }
            }
          }
        }
      }
    }

    return matches;
  }

  /// Returns `null` on a cache miss (tile not held and no bytes supplied).
  static List<GeoFeatureDto>? _handleFetchById(
    FetchFeatureByIdRequest req,
    LruCache<int, _CachedTile> cache,
  ) {
    final cached = _ensureTileCached(
      tileId: req.tileId,
      tileX: req.tileX,
      tileY: req.tileY,
      zoom: req.zoom,
      tileBytes: req.tileBytes,
      cache: cache,
    );

    if (cached == null) return req.tileBytes == null ? null : const [];

    final matches = <GeoFeatureDto>[];

    for (final layer in cached.layers) {
      if (layer.name != req.layer) continue;

      for (final feat in layer.polygonFeatures) {
        final matchesId = (req.idKey == 'id' && feat.id == req.idValue) ||
            feat.properties[req.idKey] == req.idValue;

        if (matchesId) {
          if (feat.geometry is GeometryPolygon) {
            final projected = _projectPolygonRings(
              (feat.geometry as GeometryPolygon).coordinates,
              cached.tileX,
              cached.tileY,
              cached.zoom,
              layer.extent,
            );
            matches.add(GeoFeatureDto(
              id: feat.id,
              layer: layer.name,
              properties: feat.properties,
              geometryType: feat.geometryType,
              coordinates: projected,
              touchesTileBoundary: feat.touchesBoundary,
              candidateNeighborOffsets: feat.candidateNeighborOffsets,
              sourceTile: (cached.tileX, cached.tileY, cached.zoom),
            ));
          } else if (feat.geometry is GeometryMultiPolygon) {
            final multiCoords =
                (feat.geometry as GeometryMultiPolygon).coordinates;
            if (multiCoords != null) {
              for (final poly in multiCoords) {
                final projected = _projectPolygonRings(
                  poly,
                  cached.tileX,
                  cached.tileY,
                  cached.zoom,
                  layer.extent,
                );
                if (projected.isNotEmpty) {
                  matches.add(GeoFeatureDto(
                    id: feat.id,
                    layer: layer.name,
                    properties: feat.properties,
                    geometryType: feat.geometryType,
                    coordinates: projected,
                    touchesTileBoundary: feat.touchesBoundary,
                    candidateNeighborOffsets: feat.candidateNeighborOffsets,
                    sourceTile: (cached.tileX, cached.tileY, cached.zoom),
                  ));
                }
              }
            }
          }
        }
      }
    }

    return matches;
  }

  static List<List<(double lat, double lon)>> _projectPolygonRings(
    List<dynamic> polygonRings,
    int tileX,
    int tileY,
    int zoom,
    int extent,
  ) {
    final rings = <List<(double lat, double lon)>>[];

    for (final rawRing in polygonRings) {
      if (rawRing is! List) continue;
      final doubleRing = <List<double>>[];
      for (final pt in rawRing) {
        if (pt is List && pt.length >= 2) {
          doubleRing.add(
            [(pt[0] as num).toDouble(), (pt[1] as num).toDouble()],
          );
        }
      }
      if (doubleRing.length < 3) continue;

      final clipped = PolygonClipping.clipRingToBox(
        doubleRing,
        minX: 0.0,
        minY: 0.0,
        maxX: extent.toDouble(),
        maxY: extent.toDouble(),
      );

      if (clipped.length < 3) continue;

      final projected = <(double lat, double lon)>[];
      for (final pt in clipped) {
        final latLng = TileMath.tileCoordinatesToLatLng(
          tileX: tileX,
          tileY: tileY,
          zoom: zoom,
          localX: pt[0],
          localY: pt[1],
          extent: extent,
        );
        projected.add((latLng.latitude, latLng.longitude));
      }

      if (projected.length >= 3) {
        rings.add(projected);
      }
    }

    return rings;
  }

  static List<double> _calculatePolygonBbox(List<dynamic> polygonRings) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;

    for (final rawRing in polygonRings) {
      if (rawRing is! List) continue;
      for (final pt in rawRing) {
        if (pt is List && pt.length >= 2) {
          final x = (pt[0] as num).toDouble();
          final y = (pt[1] as num).toDouble();
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    return [minX, minY, maxX, maxY];
  }

  static List<double> _calculateBbox(Geometry geom) {
    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;

    void update(double x, double y) {
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }

    if (geom is GeometryPolygon) {
      for (final ring in geom.coordinates) {
        for (final pt in ring) {
          update(pt[0], pt[1]);
        }
      }
    } else if (geom is GeometryMultiPolygon) {
      final polyCoords = geom.coordinates;
      if (polyCoords != null) {
        for (final poly in polyCoords) {
          for (final ring in poly) {
            for (final pt in ring) {
              update(pt[0], pt[1]);
            }
          }
        }
      }
    }

    return [minX, minY, maxX, maxY];
  }

  static Map<String, dynamic> _extractProperties(
    Map<String, VectorTileValue>? rawProps,
  ) {
    if (rawProps == null) return const {};
    final props = <String, dynamic>{};
    rawProps.forEach((key, val) {
      final v = val.value;
      if (v is Int64) {
        props[key] = v.toInt();
      } else {
        props[key] = v;
      }
    });
    return props;
  }
}
