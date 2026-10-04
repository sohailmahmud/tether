import 'dart:ui';

/// Converts a tap inside the preview to the 0–1 coordinates the camera
/// expects, origin at the preview's top-left corner.
Offset normalizedPreviewPoint(Offset localPosition, Size previewSize) => Offset(
  (localPosition.dx / previewSize.width).clamp(0.0, 1.0),
  (localPosition.dy / previewSize.height).clamp(0.0, 1.0),
);

/// Zoom as shown on the buttons: "0.5x", "1x", "2x", "1.4x".
String formatZoom(double zoom) {
  final tenths = (zoom * 10).round();
  return tenths % 10 == 0
      ? '${tenths ~/ 10}x'
      : '${(tenths / 10).toStringAsFixed(1)}x';
}

/// Index of the preset button covering [zoom]: the highest preset at or below
/// it. That button shows the live zoom value, as the stock camera apps do.
int activePresetIndex(List<double> presets, double zoom) {
  var active = 0;
  for (var i = 0; i < presets.length; i++) {
    if (presets[i] <= zoom + 0.01) active = i;
  }
  return active;
}
