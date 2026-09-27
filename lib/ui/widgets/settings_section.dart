import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import 'win_toggle.dart';

/// Settings card: launch-at-startup toggle + quit.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text('Start on startup',
                      style: theme.textTheme.bodyMedium),
                ),
                WinToggle(
                  value: state.launchAtStartup,
                  onChanged: state.setLaunchAtStartup,
                ),
              ],
            ),
          ),
          const Divider(),
          InkWell(
            onTap: state.quitApp,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(8)),
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Quit netturbine',
                        style: theme.textTheme.bodyMedium),
                  ),
                  Icon(Icons.close, size: 14, color: theme.hintColor),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
