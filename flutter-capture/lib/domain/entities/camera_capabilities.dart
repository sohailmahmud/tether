import 'package:equatable/equatable.dart';

/// What the opened back camera supports, read from the device at runtime
/// rather than assumed: zoom range and lenses differ between phones.
class CameraCapabilities extends Equatable {
  const CameraCapabilities({
    required this.minZoom,
    required this.maxZoom,
    required this.supportsFocusPoint,
    required this.previewAspectRatio,
  });

  /// Below 1.0 when the back camera includes an ultra-wide lens (shown as 0.5x).
  final double minZoom;
  final double maxZoom;

  /// False for fixed-focus cameras, where tap-to-focus has nothing to do.
  final bool supportsFocusPoint;

  /// Width / height of the preview in the sensor's landscape orientation.
  final double previewAspectRatio;

  /// Zoom levels for the rounded shortcut buttons, ascending.
  ///
  /// The widest available level comes first when it is below 1x (an
  /// ultra-wide lens), then 1x, then 2x, 5x and 10x where the camera reaches
  /// them. The slider and pinch cover every level in between.
  List<double> get zoomPresets {
    final base = minZoom > 1 ? minZoom : 1.0;
    return [
      if (minZoom < 1) minZoom,
      base,
      for (final level in const [2.0, 5.0, 10.0])
        if (level > base && level <= maxZoom) level,
    ];
  }

  double clampZoom(double zoom) => zoom.clamp(minZoom, maxZoom).toDouble();

  @override
  List<Object> get props => [
    minZoom,
    maxZoom,
    supportsFocusPoint,
    previewAspectRatio,
  ];
}
