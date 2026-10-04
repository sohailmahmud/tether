import 'package:flutter/material.dart';

import '../viewfinder_math.dart';

/// Rounded shortcut buttons for the zoom levels this camera supports.
class ZoomPresetButtons extends StatelessWidget {
  const ZoomPresetButtons({
    super.key,
    required this.presets,
    required this.zoom,
    required this.onSelected,
  });

  final List<double> presets;
  final double zoom;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    final active = activePresetIndex(presets, zoom);
    return DecoratedBox(
      decoration: const ShapeDecoration(
        color: Colors.black45,
        shape: StadiumBorder(),
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < presets.length; i++)
              _ZoomButton(
                label: formatZoom(i == active ? zoom : presets[i]),
                semanticLabel: 'Zoom ${formatZoom(presets[i])}',
                selected: i == active,
                onTap: () => onSelected(presets[i]),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomButton extends StatelessWidget {
  const _ZoomButton({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final size = selected ? 44.0 : 36.0;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: selected ? Colors.white24 : Colors.black54,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: size,
              height: size,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.amber : Colors.white,
                  fontSize: selected ? 13 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical slider over the full zoom range, maximum at the top.
class ZoomSlider extends StatelessWidget {
  const ZoomSlider({
    super.key,
    required this.zoom,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  final double zoom;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(color: Colors.white70, fontSize: 11);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black38,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(formatZoom(max), style: labelStyle),
            SizedBox(
              height: 200,
              width: 40,
              child: RotatedBox(
                quarterTurns: 3,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    overlayColor: Colors.white12,
                  ),
                  child: Slider(
                    value: zoom.clamp(min, max).toDouble(),
                    min: min,
                    max: max,
                    label: formatZoom(zoom),
                    semanticFormatterCallback: formatZoom,
                    onChanged: onChanged,
                  ),
                ),
              ),
            ),
            Text(formatZoom(min), style: labelStyle),
          ],
        ),
      ),
    );
  }
}
