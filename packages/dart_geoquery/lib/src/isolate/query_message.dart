import 'dart:typed_data';

/// Serializable representation of a feature sent across isolate boundary.
class GeoFeatureDto {
  final int? id;
  final String layer;
  final Map<String, dynamic> properties;
  final String geometryType;
  final List<List<(double lat, double lon)>>? coordinates;
  final bool touchesTileBoundary;
  final (int x, int y, int z)? sourceTile;

  const GeoFeatureDto({
    this.id,
    required this.layer,
    required this.properties,
    required this.geometryType,
    this.coordinates,
    this.touchesTileBoundary = false,
    this.sourceTile,
  });
}

/// Request sent to the long-lived isolate worker.
class PointQueryRequest {
  final int requestId;
  final int tileId;
  final int tileX;
  final int tileY;
  final int zoom;
  final Uint8List? tileBytes;
  final String? layer;
  final double localX;
  final double localY;
  final bool projectCoordinates;

  const PointQueryRequest({
    required this.requestId,
    required this.tileId,
    required this.tileX,
    required this.tileY,
    required this.zoom,
    this.tileBytes,
    this.layer,
    required this.localX,
    required this.localY,
    this.projectCoordinates = true,
  });
}

/// Request to fetch/stitch features across neighboring tiles by ID.
class FetchFeatureByIdRequest {
  final int requestId;
  final int tileId;
  final int tileX;
  final int tileY;
  final int zoom;
  final Uint8List? tileBytes;
  final String layer;
  final String idKey;
  final dynamic idValue;

  const FetchFeatureByIdRequest({
    required this.requestId,
    required this.tileId,
    required this.tileX,
    required this.tileY,
    required this.zoom,
    this.tileBytes,
    required this.layer,
    required this.idKey,
    required this.idValue,
  });
}

/// Response returned from the isolate worker.
class PointQueryResponse {
  final int requestId;
  final List<GeoFeatureDto> features;

  const PointQueryResponse({
    required this.requestId,
    required this.features,
  });
}

/// Command to terminate the worker isolate cleanly.
class TerminateWorkerCommand {
  const TerminateWorkerCommand();
}
