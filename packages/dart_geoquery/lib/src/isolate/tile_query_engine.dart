import 'dart:typed_data';

import 'package:fixnum/fixnum.dart';
import 'package:vector_tile/vector_tile.dart';

import '../cache/lru_cache.dart';
import '../spatial/point_in_polygon.dart';
import '../spatial/polygon_clipping.dart';
import '../spatial/tile_math.dart';
import 'query_message.dart';

/// Local tile coordinate extent that point query coordinates are expressed in.
///
/// Layers with a different extent get the point rescaled.
const int queryExtent = 4096;

class _CachedTile {
  final int tileX;
  final int tileY;
  final int zoom;
  final List<_CachedLayer> layers;

  _CachedTile({
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

/// Platform-neutral vector tile decoder and spatial matcher.
///
/// Holds an LRU cache of decoded tiles. It is used inside the background
/// isolate worker and directly on the calling isolate when no isolate is
/// available (web) or wanted (`useIsolate: false`), so both paths return
/// identical results.
class TileQueryEngine {
  final LruCache<int, _CachedTile> _cache;

  TileQueryEngine({int cacheCapacity = 64})
      : _cache = LruCache<int, _CachedTile>(capacity: cacheCapacity);

  /// Point-in-polygon query against one tile.
  ///
  /// Returns `null` on a cache miss (tile not held and no bytes supplied).
  List<GeoFeatureDto>? queryPoint(PointQueryRequest req) {
    final cached = _ensureTileCached(
      tileId: req.tileId,
      tileX: req.tileX,
      tileY: req.tileY,
      zoom: req.zoom,
      tileBytes: req.tileBytes,
    );

    if (cached == null) return req.tileBytes == null ? null : const [];

    final matches = <GeoFeatureDto>[];

    for (final layer in cached.layers) {
      if (req.layer != null && layer.name != req.layer) continue;

      final scale = layer.extent / queryExtent;
      final px = req.localX * scale;
      final py = req.localY * scale;

      for (final feat in layer.polygonFeatures) {
        final bbox = feat.bbox;
        if (px < bbox[0] || px > bbox[2] || py < bbox[1] || py > bbox[3]) {
          continue;
        }

        final geometry = feat.geometry;
        if (geometry is GeometryPolygon) {
          final isInside = PointInPolygon.containsPoint(
            px: px,
            py: py,
            rings: geometry.coordinates,
          );
          if (isInside) {
            matches.add(_dto(
              feat,
              layer,
              cached,
              _projectPolygonRings(geometry.coordinates, cached, layer.extent),
              touchesBoundary: feat.touchesBoundary,
              candidateOffsets: feat.candidateNeighborOffsets,
            ));
          }
        } else if (geometry is GeometryMultiPolygon) {
          final multiCoords = geometry.coordinates;
          if (multiCoords == null) continue;
          for (final poly in multiCoords) {
            final isInside = PointInPolygon.containsPoint(
              px: px,
              py: py,
              rings: poly,
            );
            if (!isInside) continue;

            // Boundary info for this exact matched part only.
            final (touches, offsets) =
                _boundaryInfo(_calculatePolygonBbox(poly), layer.extent);

            // Project ONLY this exact matched polygon part on demand.
            matches.add(_dto(
              feat,
              layer,
              cached,
              _projectPolygonRings(poly, cached, layer.extent),
              touchesBoundary: touches,
              candidateOffsets: offsets,
            ));
            break;
          }
        }
      }
    }

    return matches;
  }

  /// Returns every polygon part in [FetchFeatureByIdRequest.layer] whose id
  /// (or property [FetchFeatureByIdRequest.idKey]) equals the requested value.
  /// Used to stitch neighbor tile pieces.
  ///
  /// Returns `null` on a cache miss (tile not held and no bytes supplied).
  List<GeoFeatureDto>? fetchFeatureById(FetchFeatureByIdRequest req) {
    final cached = _ensureTileCached(
      tileId: req.tileId,
      tileX: req.tileX,
      tileY: req.tileY,
      zoom: req.zoom,
      tileBytes: req.tileBytes,
    );

    if (cached == null) return req.tileBytes == null ? null : const [];

    final matches = <GeoFeatureDto>[];

    for (final layer in cached.layers) {
      if (layer.name != req.layer) continue;

      for (final feat in layer.polygonFeatures) {
        final matchesId = (req.idKey == 'id' && feat.id == req.idValue) ||
            feat.properties[req.idKey] == req.idValue;
        if (!matchesId) continue;

        final geometry = feat.geometry;
        final List<List<dynamic>> parts;
        if (geometry is GeometryPolygon) {
          parts = [geometry.coordinates];
        } else if (geometry is GeometryMultiPolygon) {
          parts = geometry.coordinates ?? const [];
        } else {
          continue;
        }

        for (final poly in parts) {
          final projected = _projectPolygonRings(poly, cached, layer.extent);
          if (projected.isEmpty) continue;
          matches.add(_dto(
            feat,
            layer,
            cached,
            projected,
            touchesBoundary: feat.touchesBoundary,
            candidateOffsets: feat.candidateNeighborOffsets,
          ));
        }
      }
    }

    return matches;
  }

  GeoFeatureDto _dto(
    _CachedFeature feat,
    _CachedLayer layer,
    _CachedTile tile,
    List<List<(double lat, double lon)>> coordinates, {
    required bool touchesBoundary,
    required List<(int dx, int dy)> candidateOffsets,
  }) {
    return GeoFeatureDto(
      id: feat.id,
      layer: layer.name,
      properties: feat.properties,
      geometryType: feat.geometryType,
      coordinates: coordinates,
      touchesTileBoundary: touchesBoundary,
      candidateNeighborOffsets: candidateOffsets,
      sourceTile: (tile.tileX, tile.tileY, tile.zoom),
    );
  }

  _CachedTile? _ensureTileCached({
    required int tileId,
    required int tileX,
    required int tileY,
    required int zoom,
    required Uint8List? tileBytes,
  }) {
    var cached = _cache.get(tileId);
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
        final (touches, offsets) = _boundaryInfo(bbox, vLayer.extent);

        polygonFeatures.add(_CachedFeature(
          id: feat.id != Int64.ZERO ? feat.id.toInt() : null,
          properties: _extractProperties(feat.properties),
          geometryType: feat.geometryType?.name ?? 'Polygon',
          geometry: geom,
          bbox: bbox,
          touchesBoundary: touches,
          candidateNeighborOffsets: offsets,
        ));
      }

      cachedLayers.add(_CachedLayer(
        name: vLayer.name,
        extent: vLayer.extent,
        polygonFeatures: polygonFeatures,
      ));
    }

    cached = _CachedTile(
      tileX: tileX,
      tileY: tileY,
      zoom: zoom,
      layers: cachedLayers,
    );
    _cache.put(tileId, cached);
    return cached;
  }

  /// Whether [bbox] touches the tile edge, and which neighbors to visit.
  static (bool, List<(int dx, int dy)>) _boundaryInfo(
    List<double> bbox,
    int extent,
  ) {
    final e = extent.toDouble();
    final touchLeft = bbox[0] <= 0.0;
    final touchRight = bbox[2] >= e;
    final touchTop = bbox[1] <= 0.0;
    final touchBottom = bbox[3] >= e;
    final touches = touchLeft || touchRight || touchTop || touchBottom;
    if (!touches) return (false, const <(int dx, int dy)>[]);

    final offsets = <(int dx, int dy)>[];
    if (touchLeft) offsets.add((-1, 0));
    if (touchRight) offsets.add((1, 0));
    if (touchTop) offsets.add((0, -1));
    if (touchBottom) offsets.add((0, 1));

    if (touchLeft && touchTop) offsets.add((-1, -1));
    if (touchLeft && touchBottom) offsets.add((-1, 1));
    if (touchRight && touchTop) offsets.add((1, -1));
    if (touchRight && touchBottom) offsets.add((1, 1));

    return (true, offsets);
  }

  static List<List<(double lat, double lon)>> _projectPolygonRings(
    List<dynamic> polygonRings,
    _CachedTile tile,
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
          tileX: tile.tileX,
          tileY: tile.tileY,
          zoom: tile.zoom,
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
      props[key] = v is Int64 ? v.toInt() : v;
    });
    return props;
  }
}
