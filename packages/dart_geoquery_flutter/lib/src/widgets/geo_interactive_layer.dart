import 'dart:async';

import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../controllers/geo_selection_controller.dart';
import '../models/lat_lng_extensions.dart';
import '../models/polygon_style.dart';
import '../rendering/extrusion_geometry.dart';
import '../rendering/extrusion_painter.dart';

/// An interactive selection and highlighting layer for [FlutterMap].
///
/// Efficiently renders only the selected features using [PolygonLayer] without
/// duplicating or re-rendering base map tiles.
///
/// Set [extrude] to draw selected features as 2.5D blocks raised by their
/// height (read from [heightKey], falling back to [defaultHeightMeters]).
/// Walls and roof colors are derived from the feature's [PolygonStyle].
class GeoInteractiveLayer extends StatefulWidget {
  /// The [GeoQuery] instance used to query PMTiles data.
  final gq.GeoQuery query;

  /// Target vector layer to query and highlight (e.g. 'buildings', 'lotes').
  final String layer;

  /// Unique identifier property key (e.g. 'building_i', 'id', 'code').
  final String idKey;

  /// Selection controller tracking active selections and custom styles.
  final GeoSelectionController? controller;

  /// Callback returning custom styling for each selected feature.
  final PolygonStyle Function(gq.GeoFeature feature)? selectedStyle;

  /// Callback invoked when a feature is tapped (or null if tap hit empty space).
  final void Function(gq.GeoFeature? feature)? onFeatureTap;

  /// Debounce interval to suppress rapid consecutive map clicks.
  final Duration debounceDuration;

  /// Whether to stitch geometry across neighboring tiles when touching edges.
  final bool stitchBoundaries;

  /// Automatically select/toggle the feature in the controller upon tap.
  final bool autoSelectOnTap;

  /// Draws selected features as 2.5D extruded blocks instead of flat polygons.
  final bool extrude;

  /// Feature property holding the height in meters (used when [extrude]).
  final String heightKey;

  /// Height in meters used when [heightKey] is missing or invalid.
  final double defaultHeightMeters;

  /// Vertical squash applied to the extrusion to fake an oblique camera
  /// (`1` = full height straight up the screen).
  final double extrusionPerspective;

  const GeoInteractiveLayer({
    super.key,
    required this.query,
    required this.layer,
    this.idKey = 'id',
    this.controller,
    this.selectedStyle,
    this.onFeatureTap,
    this.debounceDuration = const Duration(milliseconds: 150),
    this.stitchBoundaries = true,
    this.autoSelectOnTap = true,
    this.extrude = false,
    this.heightKey = 'height',
    this.defaultHeightMeters = 10,
    this.extrusionPerspective = 0.7,
  }) : assert(defaultHeightMeters > 0),
       assert(extrusionPerspective > 0);

  @override
  State<GeoInteractiveLayer> createState() => GeoInteractiveLayerState();
}

class GeoInteractiveLayerState extends State<GeoInteractiveLayer> {
  late GeoSelectionController _controller;
  Timer? _debounceTimer;
  int _activeQueryToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? GeoSelectionController();
  }

  @override
  void didUpdateWidget(covariant GeoInteractiveLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != null && widget.controller != _controller) {
      _controller = widget.controller!;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  /// Handles a map click at [point] (conveniently wireable to [MapOptions.onTap]).
  Future<gq.GeoFeature?> handleTap(ll.LatLng point) async {
    _debounceTimer?.cancel();
    final completer = Completer<gq.GeoFeature?>();

    _debounceTimer = Timer(widget.debounceDuration, () async {
      final currentToken = ++_activeQueryToken;

      try {
        final feature = await widget.query.at(
          point.toGeoQuery(),
          layer: widget.layer,
          stitchBoundaries: widget.stitchBoundaries,
          idKey: widget.idKey,
        );

        // Cancel if a newer query has been dispatched
        if (currentToken != _activeQueryToken || !mounted) {
          completer.complete(null);
          return;
        }

        if (widget.autoSelectOnTap) {
          if (feature != null) {
            final style = widget.selectedStyle?.call(feature);
            _controller.toggle(feature, idKey: widget.idKey, style: style);
          }
        }

        widget.onFeatureTap?.call(feature);
        completer.complete(feature);
      } catch (e) {
        completer.complete(null);
      }
    });

    return completer.future;
  }

  PolygonStyle _styleFor(gq.GeoFeature feature, PolygonStyle? customStyle) =>
      customStyle ??
      widget.selectedStyle?.call(feature) ??
      const PolygonStyle();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) =>
          widget.extrude ? _buildExtruded(context) : _buildFlat(),
    );
  }

  Widget _buildExtruded(BuildContext context) {
    final camera = MapCamera.of(context);
    final shapes = <ExtrudedShape>[];

    for (final (feature, customStyle) in _controller.selectedMap.values) {
      final rings = feature.coordinates;
      if (rings == null || rings.isEmpty || rings.first.length < 3) continue;

      final outer = rings.first;
      final latitude =
          outer.fold<double>(0, (sum, p) => sum + p.latitude) / outer.length;
      final heightMeters = ExtrusionGeometry.resolveHeight(
        feature.properties,
        widget.heightKey,
        widget.defaultHeightMeters,
      );
      final liftPx = ExtrusionGeometry.heightToPixels(
        heightMeters: heightMeters,
        latitude: latitude,
        zoom: camera.zoom,
        perspective: widget.extrusionPerspective,
      );

      shapes.add(
        ExtrudedShape(
          footprint: [
            for (final ring in rings)
              [
                for (final p in ring)
                  camera.latLngToScreenOffset(p.toLatLong2()),
              ],
          ],
          lift: Offset(0, -liftPx),
          style: _styleFor(feature, customStyle),
        ),
      );
    }

    return IgnorePointer(
      child: SizedBox.expand(
        child: CustomPaint(painter: GeoExtrusionPainter(shapes)),
      ),
    );
  }

  Widget _buildFlat() {
    final polygons = <Polygon>[];

    for (final entry in _controller.selectedMap.entries) {
      final (feature, customStyle) = entry.value;
      final style = _styleFor(feature, customStyle);

      final rings = feature.coordinates;
      if (rings == null || rings.isEmpty) continue;

      // Outer boundary
      final outerPoints = rings.first.map((c) => c.toLatLong2()).toList();

      // Interior holes
      List<List<ll.LatLng>>? holePointsList;
      if (rings.length > 1) {
        holePointsList = rings
            .skip(1)
            .map((hole) => hole.map((c) => c.toLatLong2()).toList())
            .toList();
      }

      polygons.add(
        Polygon(
          points: outerPoints,
          holePointsList: holePointsList,
          color: style.color,
          borderColor: style.borderColor,
          borderStrokeWidth: style.borderStrokeWidth,
          pattern: style.isDotted
              ? const StrokePattern.dotted()
              : const StrokePattern.solid(),
          label: style.label,
          labelStyle: style.labelStyle ?? const TextStyle(),
        ),
      );
    }

    return PolygonLayer(polygonCulling: false, polygons: polygons);
  }
}
