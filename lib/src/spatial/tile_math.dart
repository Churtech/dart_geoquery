import 'dart:math' as math;
import '../models/lat_lng.dart';

/// Web Mercator (EPSG:3857) projection utilities for tile math.
class TileMath {
  /// Maximum latitude representable in Web Mercator projection.
  static const double maxMercatorLat = 85.05112877980659;

  /// Clamps latitude to valid Web Mercator range.
  static double clampLat(double lat) =>
      lat.clamp(-maxMercatorLat, maxMercatorLat);

  /// Converts [LatLng] to continuous tile coordinates `(x, y)` at a given [zoom].
  static (double x, double y) latLngToContinuousTile(LatLng point, int zoom) {
    final lat = clampLat(point.latitude);
    final lon = point.longitude;
    final n = math.pow(2.0, zoom);

    final x = (lon + 180.0) / 360.0 * n;
    final latRad = lat * math.pi / 180.0;
    final y = (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) / 2.0 * n;

    return (x, y);
  }

  /// Converts [LatLng] to integer tile coordinates `(x, y)` at a given [zoom].
  static (int x, int y) latLngToTile(LatLng point, int zoom) {
    final (contX, contY) = latLngToContinuousTile(point, zoom);
    final maxTile = (1 << zoom) - 1;
    final x = contX.floor().clamp(0, maxTile);
    final y = contY.floor().clamp(0, maxTile);
    return (x, y);
  }

  /// Converts [LatLng] to local pixel/extent coordinates `(localX, localY)`
  /// within the tile containing that point at a given [zoom].
  ///
  /// [extent] is the tile coordinate space resolution (usually 4096 in MVT).
  static (double localX, double localY) latLngToTileCoordinates({
    required LatLng point,
    required int zoom,
    required int extent,
  }) {
    final (contX, contY) = latLngToContinuousTile(point, zoom);
    final tileX = contX.floor();
    final tileY = contY.floor();

    final fracX = contX - tileX;
    final fracY = contY - tileY;

    final localX = fracX * extent;
    final localY = fracY * extent;

    return (localX, localY);
  }

  /// Converts tile local coordinates `(localX, localY)` within tile `(tileX, tileY)`
  /// at [zoom] back to a [LatLng].
  static LatLng tileCoordinatesToLatLng({
    required int tileX,
    required int tileY,
    required int zoom,
    required double localX,
    required double localY,
    required int extent,
  }) {
    final n = math.pow(2.0, zoom);
    final contX = tileX + (localX / extent);
    final contY = tileY + (localY / extent);

    final lon = contX / n * 360.0 - 180.0;
    final latRad = math.atan(_sinh(math.pi * (1.0 - 2.0 * contY / n)));
    final lat = latRad * 180.0 / math.pi;

    return LatLng(lat, lon);
  }

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2.0;
}
