import 'package:dart_geoquery/dart_geoquery.dart' as gq;
import 'package:flutter/foundation.dart';
import '../models/polygon_style.dart';

/// Reactive selection controller for vector features displayed in flutter_map.
class GeoSelectionController extends ChangeNotifier {
  final Map<dynamic, (gq.GeoFeature feature, PolygonStyle? style)> _selected = {};

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

  /// Selects a [feature].
  void select(
    gq.GeoFeature feature, {
    String idKey = 'id',
    PolygonStyle? style,
  }) {
    final id = idKey == 'id' ? feature.id : feature.properties[idKey];
    if (id == null) return;

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
    final id = idKey == 'id' ? feature.id : feature.properties[idKey];
    if (id == null) return;

    if (_selected.containsKey(id)) {
      _selected.remove(id);
    } else {
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
