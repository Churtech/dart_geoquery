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
  final List<List<(double lat, double lon)>> projectedRings;

  _CachedFeature({
    this.id,
    required this.properties,
    required this.geometryType,
    required this.geometry,
    required this.bbox,
    required this.touchesBoundary,
    required this.candidateNeighborOffsets,
    required this.projectedRings,
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
        completer?.complete(message.features);
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
          features: results,
        ));
      } else if (message is FetchFeatureByIdRequest) {
        final results = _handleFetchById(message, tileCache);
        replyPort?.send(PointQueryResponse(
          requestId: message.requestId,
          features: results,
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

        // Sutherland-Hodgman clipping against [0, extent] before WGS84 projection
        final projectedRings = _projectClippedRings(
          geom,
          tileX,
          tileY,
          zoom,
          extent,
        );

        polygonFeatures.add(_CachedFeature(
          id: id,
          properties: props,
          geometryType: feat.geometryType?.name ?? 'Polygon',
          geometry: geom,
          bbox: bbox,
          touchesBoundary: touches,
          candidateNeighborOffsets: candidateOffsets,
          projectedRings: projectedRings,
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

  static List<GeoFeatureDto> _handlePointQuery(
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

    if (cached == null) return const [];

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

        final isInside = _testGeometryContains(feat.geometry, px, py);
        if (isInside) {
          matches.add(GeoFeatureDto(
            id: feat.id,
            layer: layer.name,
            properties: feat.properties,
            geometryType: feat.geometryType,
            coordinates: feat.projectedRings,
            touchesTileBoundary: feat.touchesBoundary,
            candidateNeighborOffsets: feat.candidateNeighborOffsets,
            sourceTile: (cached.tileX, cached.tileY, cached.zoom),
          ));
        }
      }
    }

    return matches;
  }

  static List<GeoFeatureDto> _handleFetchById(
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

    if (cached == null) return const [];

    final matches = <GeoFeatureDto>[];

    for (final layer in cached.layers) {
      if (layer.name != req.layer) continue;

      for (final feat in layer.polygonFeatures) {
        final matchesId = (req.idKey == 'id' && feat.id == req.idValue) ||
            feat.properties[req.idKey] == req.idValue;

        if (matchesId) {
          matches.add(GeoFeatureDto(
            id: feat.id,
            layer: layer.name,
            properties: feat.properties,
            geometryType: feat.geometryType,
            coordinates: feat.projectedRings,
            touchesTileBoundary: feat.touchesBoundary,
            candidateNeighborOffsets: feat.candidateNeighborOffsets,
            sourceTile: (cached.tileX, cached.tileY, cached.zoom),
          ));
        }
      }
    }

    return matches;
  }

  static List<List<(double lat, double lon)>> _projectClippedRings(
    Geometry geom,
    int tileX,
    int tileY,
    int zoom,
    int extent,
  ) {
    final rings = <List<(double lat, double lon)>>[];

    void processRing(List<List<double>> rawRing) {
      // 1. Sutherland-Hodgman clipping against exact tile boundary
      final clipped = PolygonClipping.clipRingToBox(
        rawRing,
        minX: 0.0,
        minY: 0.0,
        maxX: extent.toDouble(),
        maxY: extent.toDouble(),
      );

      if (clipped.length < 3) return;

      // 2. Project clipped vertices to WGS84 LatLng
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

    if (geom is GeometryPolygon) {
      for (final ring in geom.coordinates) {
        processRing(ring);
      }
    } else if (geom is GeometryMultiPolygon) {
      final polyCoords = geom.coordinates;
      if (polyCoords != null) {
        for (final poly in polyCoords) {
          for (final ring in poly) {
            processRing(ring);
          }
        }
      }
    }

    return rings;
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

  static bool _testGeometryContains(Geometry geom, double px, double py) {
    if (geom is GeometryPolygon) {
      return PointInPolygon.containsPoint(
        px: px,
        py: py,
        rings: geom.coordinates,
      );
    } else if (geom is GeometryMultiPolygon) {
      final coords = geom.coordinates;
      if (coords == null) return false;
      return PointInPolygon.containsPointInMultiPolygon(
        px: px,
        py: py,
        multiPolygon: coords,
      );
    }
    return false;
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
