import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:tether_capture/presentation/camera/viewfinder_math.dart';

void main() {
  test('a tap maps to 0–1 coordinates across the preview', () {
    const preview = Size(360, 480);
    expect(
      normalizedPreviewPoint(const Offset(180, 120), preview),
      const Offset(0.5, 0.25),
    );
    expect(normalizedPreviewPoint(Offset.zero, preview), Offset.zero);
    expect(
      normalizedPreviewPoint(const Offset(360, 480), preview),
      const Offset(1, 1),
    );
  });

  test('taps on the edge never leave the 0–1 range', () {
    expect(
      normalizedPreviewPoint(const Offset(-4, 500), const Size(360, 480)),
      const Offset(0, 1),
    );
  });

  test('zoom labels drop needless decimals', () {
    expect(formatZoom(0.5), '0.5x');
    expect(formatZoom(1), '1x');
    expect(formatZoom(1.04), '1x');
    expect(formatZoom(1.44), '1.4x');
    expect(formatZoom(0.55), '0.6x');
    expect(formatZoom(10), '10x');
  });

  test('the active button is the highest preset at or below the zoom', () {
    const presets = [0.5, 1.0, 2.0, 5.0];
    expect(activePresetIndex(presets, 0.5), 0);
    expect(activePresetIndex(presets, 0.8), 0);
    expect(activePresetIndex(presets, 1), 1);
    expect(activePresetIndex(presets, 1.9), 1);
    expect(activePresetIndex(presets, 2), 2);
    expect(activePresetIndex(presets, 8), 3);
  });
}
