import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'query_message.dart';
import 'query_worker.dart';
import 'tile_query_engine.dart';

/// Long-lived background Isolate worker for vector tile decoding and spatial
/// queries. It runs a [TileQueryEngine] inside the spawned isolate.
class IsolateQueryWorker implements QueryWorker {
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
  @override
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
  @override
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
  @override
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
    final engine = TileQueryEngine(cacheCapacity: cacheCapacity);

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
        final results = engine.queryPoint(message);
        replyPort?.send(PointQueryResponse(
          requestId: message.requestId,
          features: results ?? const [],
          cacheMiss: results == null,
        ));
      } else if (message is FetchFeatureByIdRequest) {
        final results = engine.fetchFeatureById(message);
        replyPort?.send(PointQueryResponse(
          requestId: message.requestId,
          features: results ?? const [],
          cacheMiss: results == null,
        ));
      }
    });
  }
}
