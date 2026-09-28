import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import 'flyout_select.dart';

/// Fan control source picker: Automatic / Fixed speed / named profiles,
/// plus "New profile…" which duplicates the active profile into a custom
/// one. Rendered as a Windows 11-style combo box ([NtSelect]).
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.state});

  final AppState state;

  static const _auto = 'auto';
  static const _fixed = 'fixed';
  static const _newProfile = 'new';
  static const _profilePrefix = 'profile:';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = switch (state.fanMode) {
      FanMode.auto => _auto,
      FanMode.fixed => _fixed,
      FanMode.profile => '$_profilePrefix${state.activeProfileId}',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child:
                  Text('Fan control', style: theme.textTheme.bodyMedium),
            ),
            NtSelect<String>(
              value: state.fanMode == FanMode.profile &&
                      state.activeProfile == null
                  ? _auto
                  : value,
              items: [
                const NtSelectItem(
                    value: _auto, label: 'Automatic'),
                const NtSelectItem(
                    value: _fixed, label: 'Fixed speed'),
                const NtSelectDivider(),
                for (final p in state.profiles)
                  NtSelectItem(
                      value: '$_profilePrefix${p.id}',
                      label: p.name),
                const NtSelectDivider(),
                const NtSelectItem(
                    value: _newProfile,
                    label: 'New profile…',
                    icon: Icons.add),
              ],
              onChanged: (v) {
                if (v == _auto) {
                  state.selectAuto();
                } else if (v == _fixed) {
                  state.selectFixed();
                } else if (v == _newProfile) {
                  state.duplicateProfile();
                } else if (v.startsWith(_profilePrefix)) {
                  state.selectProfile(v.substring(_profilePrefix.length));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
