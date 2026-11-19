import 'dart:async';
import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../controllers/geo_selection_controller.dart';
import '../models/lat_lng_extensions.dart';
import '../models/polygon_style.dart';

/// An interactive selection and highlighting layer for [FlutterMap].
///
/// Efficiently renders only the selected features using [PolygonLayer] without
/// duplicating or re-rendering base map tiles.
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
  });

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

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final polygons = <Polygon>[];

        for (final entry in _controller.selectedMap.entries) {
          final (feature, customStyle) = entry.value;
          final style = customStyle ??
              widget.selectedStyle?.call(feature) ??
              const PolygonStyle();

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

        return PolygonLayer(
          polygonCulling: false,
          polygons: polygons,
        );
      },
    );
  }
}
