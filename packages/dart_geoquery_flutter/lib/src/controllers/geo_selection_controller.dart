import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:flutter/foundation.dart';
import '../models/polygon_style.dart';

/// Reactive selection controller for vector features displayed in flutter_map.
class GeoSelectionController extends ChangeNotifier {
  /// Whether multiple features can be selected simultaneously. Defaults to true.
  final bool multiSelect;

  final Map<dynamic, (gq.GeoFeature feature, PolygonStyle? style)> _selected = {};

  GeoSelectionController({this.multiSelect = true});

  /// Current set of selected feature IDs.
  Set<dynamic> get selectedIds => _selected.keys.toSet();

  /// List of currently selected [GeoFeature] objects.
  List<gq.GeoFeature> get selectedFeatures =>
      _selected.values.map((v) => v.$1).toList();

  /// Map of selected features and their custom styles.
  Map<dynamic, (gq.GeoFeature feature, PolygonStyle? style)> get selectedMap =>
      Map.unmodifiable(_selected);

  /// Checks if feature with [id] is selected.
  bool isSelected(dynamic id) => _selected.containsKey(id);

  dynamic _resolveId(gq.GeoFeature feature, String idKey) {
    final rawId = idKey == 'id' ? feature.id : feature.properties[idKey];
    if (rawId != null && feature.geometryType != 'MultiPolygon') {
      return rawId;
    }
    if (feature.coordinates != null && feature.coordinates!.isNotEmpty) {
      final firstPoint = feature.coordinates!.first.first;
      final latStr = firstPoint.latitude.toStringAsFixed(6);
      final lngStr = firstPoint.longitude.toStringAsFixed(6);
      return rawId != null
          ? '${rawId}_${latStr}_$lngStr'
          : 'feat_${latStr}_$lngStr';
    }
    return rawId ?? feature.hashCode;
  }

  /// Selects a [feature].
  void select(
    gq.GeoFeature feature, {
    String idKey = 'id',
    PolygonStyle? style,
  }) {
    if (!multiSelect) {
      _selected.clear();
    }
    final id = _resolveId(feature, idKey);
    _selected[id] = (feature, style);
    notifyListeners();
  }

  /// Deselects feature by [id].
  void deselect(dynamic id) {
    if (_selected.remove(id) != null) {
      notifyListeners();
    }
  }

  /// Toggles selection of [feature].
  void toggle(
    gq.GeoFeature feature, {
    String idKey = 'id',
    PolygonStyle? style,
  }) {
    final id = _resolveId(feature, idKey);
    if (_selected.containsKey(id)) {
      _selected.remove(id);
    } else {
      if (!multiSelect) {
        _selected.clear();
      }
      _selected[id] = (feature, style);
    }
    notifyListeners();
  }

  /// Clears all selections.
  void clear() {
    if (_selected.isNotEmpty) {
      _selected.clear();
      notifyListeners();
    }
  }
}
