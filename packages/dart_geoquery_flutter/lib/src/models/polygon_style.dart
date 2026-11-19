import 'package:flutter/material.dart';

/// Styling options for selected vector polygons rendered in flutter_map.
class PolygonStyle {
  /// Fill color of the polygon.
  final Color color;

  /// Border/stroke color of the polygon.
  final Color borderColor;

  /// Stroke width of the polygon boundary in pixels.
  final double borderStrokeWidth;

  /// Whether the border should be drawn with a dotted pattern.
  final bool isDotted;

  /// Optional label to display at polygon center.
  final String? label;

  /// Text style for the polygon label.
  final TextStyle? labelStyle;

  const PolygonStyle({
    this.color = const Color(0x66009688), // Semi-transparent teal
    this.borderColor = const Color(0xFF00796B),
    this.borderStrokeWidth = 2.0,
    this.isDotted = false,
    this.label,
    this.labelStyle,
  });
}
