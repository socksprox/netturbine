import 'package:flutter/material.dart';

import '../../app/app_state.dart';

/// Fan control source picker: Automatic / Fixed speed / named profiles.
/// "New profile…" duplicates the active profile into a custom one.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.state});

  final AppState state;

  static const _newProfile = '__new_profile__';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = switch (state.fanMode) {
      FanMode.auto => 'auto',
      FanMode.fixed => 'fixed',
      // A missing profile id (e.g. deleted from under us) must not produce
      // a value with no matching dropdown item — fall back visually.
      FanMode.profile => state.activeProfile != null
          ? 'profile:${state.activeProfileId}'
          : 'auto',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(
              child:
                  Text('Fan control', style: theme.textTheme.bodyMedium),
            ),
            DropdownButton<String>(
              value: value,
              underline: const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(8),
              isDense: true,
              items: [
                const DropdownMenuItem(
                    value: 'auto', child: Text('Automatic')),
                const DropdownMenuItem(
                    value: 'fixed', child: Text('Fixed speed')),
                for (final p in state.profiles)
                  DropdownMenuItem(
                      value: 'profile:${p.id}', child: Text(p.name)),
                const DropdownMenuItem(
                    value: _newProfile, child: Text('New profile…')),
              ],
              onChanged: (v) {
                if (v == 'auto') {
                  state.selectAuto();
                } else if (v == 'fixed') {
                  state.selectFixed();
                } else if (v == _newProfile) {
                  state.duplicateProfile();
                } else if (v != null && v.startsWith('profile:')) {
                  state.selectProfile(v.substring(8));
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
