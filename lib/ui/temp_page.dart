import 'package:flutter/material.dart';

import '../app/app_state.dart';

/// Temperature tab: live sensor readouts, no controls.
class TempPage extends StatelessWidget {
  const TempPage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (state.sensors.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            'No temperature sensors detected on this machine.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    return Column(
      children: [
        for (final s in state.sensors) ...[
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Row(
                children: [
                  Icon(Icons.thermostat,
                      size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child:
                        Text(s.label, style: theme.textTheme.titleMedium),
                  ),
                  Text(
                    s.celsius != null ? '${s.celsius} °C' : '—',
                    style: theme.textTheme.titleLarge,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
