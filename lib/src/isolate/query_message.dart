import 'dart:typed_data';

/// Serializable representation of a feature sent across isolate boundary.
class GeoFeatureDto {
  final int? id;
  final String layer;
  final Map<String, dynamic> properties;
  final String geometryType;

  const GeoFeatureDto({
    this.id,
    required this.layer,
    required this.properties,
    required this.geometryType,
  });
}

/// Request sent to the long-lived isolate worker.
class PointQueryRequest {
  final int requestId;
  final int tileId;
  final Uint8List? tileBytes;
  final String? layer;
  final double localX;
  final double localY;

  const PointQueryRequest({
    required this.requestId,
    required this.tileId,
    this.tileBytes,
    this.layer,
    required this.localX,
    required this.localY,
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
