import 'package:flutter/material.dart';

import '../../../data/datasources/mock_server_settings.dart';

/// Bottom sheet for choosing how the mock upload server behaves.
class MockServerSheet extends StatelessWidget {
  const MockServerSheet({
    super.key,
    required this.mode,
    required this.onSelected,
  });

  final MockServerMode mode;
  final ValueChanged<MockServerMode> onSelected;

  static String label(MockServerMode mode) => switch (mode) {
    MockServerMode.normal => 'Normal',
    MockServerMode.slowConnection => 'Slow connection',
    MockServerMode.serverError => 'Server error',
    MockServerMode.unstable => 'Unstable connection',
  };

  /// For the app bar, where a long name would squeeze the screen title.
  static String shortLabel(MockServerMode mode) => switch (mode) {
    MockServerMode.normal => 'Normal',
    MockServerMode.slowConnection => 'Slow',
    MockServerMode.serverError => 'Server error',
    MockServerMode.unstable => 'Unstable',
  };

  static String _description(MockServerMode mode) => switch (mode) {
    MockServerMode.normal => 'Uploads succeed after a realistic transfer time.',
    MockServerMode.slowConnection =>
      'Bandwidth so low that uploads time out after 8 s.',
    MockServerMode.serverError => 'The server answers 503 Service Unavailable.',
    MockServerMode.unstable => 'About half of the uploads drop part-way.',
  };

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 4),
              child: Text('Mock server', style: textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                'There is no real backend, so uploads go to a simulated server. '
                'Airplane mode makes every upload fail as "no internet", whatever '
                'is chosen here.',
                style: textTheme.bodySmall,
              ),
            ),
            RadioGroup<MockServerMode>(
              groupValue: mode,
              onChanged: (selected) {
                if (selected != null) onSelected(selected);
              },
              child: Column(
                children: [
                  for (final option in MockServerMode.values)
                    RadioListTile<MockServerMode>(
                      value: option,
                      title: Text(label(option)),
                      subtitle: Text(_description(option)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
