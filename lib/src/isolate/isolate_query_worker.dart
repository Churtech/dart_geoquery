import 'dart:async';
import 'dart:isolate';

import 'package:fixnum/fixnum.dart';
import 'package:vector_tile/vector_tile.dart';

import '../cache/lru_cache.dart';
import '../spatial/point_in_polygon.dart';
import 'query_message.dart';

/// Internal indexed representation of a decoded tile cached inside the isolate.
class _CachedTile {
  final int tileId;
  final List<_CachedLayer> layers;

  _CachedTile({required this.tileId, required this.layers});
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
  // Pre-calculated bounding box [minX, minY, maxX, maxY]
  final List<double> bbox;

  _CachedFeature({
    this.id,
    required this.properties,
    required this.geometryType,
    required this.geometry,
    required this.bbox,
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
    required double localX,
    required double localY,
    String? layer,
    dynamic tileBytes,
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
      tileBytes: tileBytes,
      layer: layer,
      localX: localX,
      localY: localY,
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
      }
    });
  }

  static List<GeoFeatureDto> _handlePointQuery(
    PointQueryRequest req,
    LruCache<int, _CachedTile> cache,
  ) {
    var cached = cache.get(req.tileId);

    // If not cached and bytes are provided, decode and index
    if (cached == null && req.tileBytes != null && req.tileBytes!.isNotEmpty) {
      final vTile = VectorTile.fromBytes(bytes: req.tileBytes!);
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

          polygonFeatures.add(_CachedFeature(
            id: id,
            properties: props,
            geometryType: feat.geometryType?.name ?? 'Polygon',
            geometry: geom,
            bbox: bbox,
          ));
        }

        cachedLayers.add(_CachedLayer(
          name: vLayer.name,
          extent: vLayer.extent,
          polygonFeatures: polygonFeatures,
        ));
      }

      cached = _CachedTile(tileId: req.tileId, layers: cachedLayers);
      cache.put(req.tileId, cached);
    }

    if (cached == null) return const [];

    final matches = <GeoFeatureDto>[];
    final px = req.localX;
    final py = req.localY;

    for (final layer in cached.layers) {
      if (req.layer != null && layer.name != req.layer) continue;

      for (final feat in layer.polygonFeatures) {
        // 1. Fast bounding box rejection O(1)
        final bbox = feat.bbox;
        if (px < bbox[0] || px > bbox[2] || py < bbox[1] || py > bbox[3]) {
          continue;
        }

        // 2. Exact Point-in-polygon ray casting
        final isInside = _testGeometryContains(feat.geometry, px, py);
        if (isInside) {
          matches.add(GeoFeatureDto(
            id: feat.id,
            layer: layer.name,
            properties: feat.properties,
            geometryType: feat.geometryType,
          ));
        }
      }
    }

    return matches;
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
