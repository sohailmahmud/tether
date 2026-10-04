import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/domain/entities/camera_capabilities.dart';

CameraCapabilities _camera(double min, double max) => CameraCapabilities(
  minZoom: min,
  maxZoom: max,
  supportsFocusPoint: true,
  previewAspectRatio: 4 / 3,
);

void main() {
  group('zoom presets', () {
    test('a camera without ultra-wide gets no 0.5x button', () {
      // The test phone (Galaxy A04s) reports 1x–8x.
      expect(_camera(1, 8).zoomPresets, [1, 2, 5]);
    });

    test('an ultra-wide lens adds its widest level first', () {
      expect(_camera(0.5, 10).zoomPresets, [0.5, 1, 2, 5, 10]);
      expect(_camera(0.6, 4).zoomPresets, [0.6, 1, 2]);
    });

    test('only levels the camera reaches are offered', () {
      expect(_camera(1, 1.8).zoomPresets, [1]);
      expect(_camera(1, 2).zoomPresets, [1, 2]);
    });

    test('a camera whose zoom starts above 1x starts there', () {
      expect(_camera(1.2, 6).zoomPresets, [1.2, 2, 5]);
    });
  });

  test('zoom is clamped to the supported range', () {
    final camera = _camera(0.5, 8);
    expect(camera.clampZoom(0.1), 0.5);
    expect(camera.clampZoom(3), 3);
    expect(camera.clampZoom(20), 8);
  });
}
