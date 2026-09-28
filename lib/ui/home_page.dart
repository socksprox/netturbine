import 'package:flutter/material.dart';

import '../app/app_state.dart';
import 'temp_page.dart';
import 'widgets/boost_button.dart';
import 'widgets/fan_card.dart';
import 'widgets/segmented_selector.dart';
import 'widgets/settings_section.dart';

/// Compact popover-style body shown when the tray icon is clicked.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.state});

  final AppState state;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    return Scaffold(
      // The HWND is borderless (flyout): paint the flyout's 1px outline and
      // rounded corners here, matching the DWM corner clip in the runner.
      body: Container(
        decoration: BoxDecoration(
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.wind_power,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text('netturbine', style: theme.textTheme.titleLarge),
                  ],
                ),
                const SizedBox(height: 12),
                SegmentedSelector<int>(
                  options: const [
                    SegmentOption(
                      value: 0,
                      label: 'Fan Control',
                      icon: Icons.wind_power,
                    ),
                    SegmentOption(
                      value: 1,
                      label: 'Temperature',
                      icon: Icons.thermostat,
                    ),
                  ],
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _FanTab(state: state),
                      ListView(children: [TempPage(state: state)]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FanTab extends StatelessWidget {
  const _FanTab({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      children: [
        if (state.backendError)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber,
                    size: 16,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fan backend unavailable.',
                      style: theme.textTheme.bodySmall,
                    ),
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
    );
  }
}
