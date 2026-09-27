import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'widgets/boost_button.dart';
import 'widgets/fan_card.dart';
import 'widgets/settings_section.dart';

/// Compact popover-style body shown when the tray icon is clicked.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Icon(Icons.wind_power,
                    size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('netturbine', style: theme.textTheme.titleLarge),
              ],
            ),
            const SizedBox(height: 16),
            if (state.backendError)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber,
                          size: 16, color: theme.colorScheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('Fan backend unavailable.',
                            style: theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ),
            if (state.fans.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'No controllable fans detected on this machine.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              )
            else
              for (final fan in state.fans) ...[
                FanCard(fan: fan, state: state),
                const SizedBox(height: 8),
              ],
            const SizedBox(height: 8),
            BoostButton(state: state),
            const SizedBox(height: 8),
            SettingsSection(state: state),
          ],
        ),
      ),
    );
  }
}
