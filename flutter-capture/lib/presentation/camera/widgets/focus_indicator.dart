import 'package:flutter/material.dart';

/// Square drawn where the user tapped to focus. Shrinks into place, holds,
/// then fades. Give it a new key per tap to replay the animation.
class FocusIndicator extends StatefulWidget {
  const FocusIndicator({super.key});

  static const size = 64.0;

  @override
  State<FocusIndicator> createState() => _FocusIndicatorState();
}

class _FocusIndicatorState extends State<FocusIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  late final Animation<double> _scale = Tween(begin: 1.4, end: 1.0).animate(
    CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.2, curve: Curves.easeOut),
    ),
  );

  late final Animation<double> _opacity = Tween(begin: 1.0, end: 0.0).animate(
    CurvedAnimation(parent: _controller, curve: const Interval(0.75, 1)),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          child: Container(
            width: FocusIndicator.size,
            height: FocusIndicator.size,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.amber, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
    );
  }
}
