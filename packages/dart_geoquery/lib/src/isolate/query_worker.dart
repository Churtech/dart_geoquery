import 'dart:typed_data';

import 'query_message.dart';
import 'tile_query_engine.dart';

/// Executes tile decoding and spatial matching for [GeoQuery].
///
/// Implementations either run in a background isolate (native platforms) or
/// on the calling isolate ([InProcessQueryWorker], used on web and with
/// `useIsolate: false`). Both throw [TileCacheMissException] when they no
/// longer hold a tile and no [tileBytes] were supplied, so the caller can
/// resend the bytes.
abstract interface class QueryWorker {
  /// Point-in-polygon query; [localX]/[localY] are in a 4096 tile extent.
  Future<List<GeoFeatureDto>> queryPoint({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required double localX,
    required double localY,
    String? layer,
    Uint8List? tileBytes,
  });

  /// Fetches the parts of a feature by id in one tile (boundary stitching).
  Future<List<GeoFeatureDto>> fetchFeatureById({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required String layer,
    required String idKey,
    required dynamic idValue,
    Uint8List? tileBytes,
  });

  /// Releases the worker's resources.
  void close();
}

/// [QueryWorker] that runs the [TileQueryEngine] on the calling isolate.
class InProcessQueryWorker implements QueryWorker {
  final TileQueryEngine _engine;

  InProcessQueryWorker({int cacheCapacity = 64})
      : _engine = TileQueryEngine(cacheCapacity: cacheCapacity);

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
  }) async {
    final result = _engine.queryPoint(PointQueryRequest(
      requestId: 0,
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      tileBytes: tileBytes,
      layer: layer,
      localX: localX,
      localY: localY,
    ));
    if (result == null) throw const TileCacheMissException();
    return result;
  }

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
  }) async {
    final result = _engine.fetchFeatureById(FetchFeatureByIdRequest(
      requestId: 0,
      tileId: tileId,
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      tileBytes: tileBytes,
      layer: layer,
      idKey: idKey,
      idValue: idValue,
    ));
    if (result == null) throw const TileCacheMissException();
    return result;
  }

  @override
  void close() {}
}
