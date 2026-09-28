import 'package:flutter/material.dart';

import '../../app/app_state.dart';

/// Fan control source picker: Automatic / Fixed speed / named profiles.
/// Combo-box look: a bordered button opening a flyout menu where the
/// active source carries a leading check, like Windows 11 flyout items.
/// "New profile…" duplicates the active profile into a custom one.
class ModeSelector extends StatelessWidget {
  const ModeSelector({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = switch (state.fanMode) {
      FanMode.auto => 'Automatic',
      FanMode.fixed => 'Fixed speed',
      FanMode.profile => state.activeProfile?.name ?? 'Automatic',
    };

    Widget item({
      required String label,
      required bool selected,
      IconData? icon,
      VoidCallback? onPressed,
    }) {
      return MenuItemButton(
        onPressed: onPressed,
        style: MenuItemButton.styleFrom(
          minimumSize: const Size.fromHeight(32),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
        leadingIcon: SizedBox(
          width: 16,
          child: selected
              ? Icon(Icons.check,
                  size: 14, color: theme.colorScheme.primary)
              : icon != null
                  ? Icon(icon, size: 14, color: theme.hintColor)
                  : null,
        ),
        child: Text(label, style: theme.textTheme.bodyMedium),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              child:
                  Text('Fan control', style: theme.textTheme.bodyMedium),
            ),
            MenuAnchor(
              style: MenuStyle(
                minimumSize:
                    const WidgetStatePropertyAll(Size(180, 0)),
                padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(vertical: 4)),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: theme.dividerColor),
                )),
              ),
              menuChildren: [
                item(
                  label: 'Automatic',
                  selected: state.fanMode == FanMode.auto,
                  onPressed: state.selectAuto,
                ),
                item(
                  label: 'Fixed speed',
                  selected: state.fanMode == FanMode.fixed,
                  onPressed: state.selectFixed,
                ),
                const Divider(height: 8),
                for (final p in state.profiles)
                  item(
                    label: p.name,
                    selected: state.fanMode == FanMode.profile &&
                        state.activeProfileId == p.id,
                    onPressed: () => state.selectProfile(p.id),
                  ),
                const Divider(height: 8),
                item(
                  label: 'New profile…',
                  selected: false,
                  icon: Icons.add,
                  onPressed: state.duplicateProfile,
                ),
              ],
              builder: (context, controller, child) {
                return OutlinedButton(
                  onPressed: () => controller.isOpen
                      ? controller.close()
                      : controller.open(),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    minimumSize: Size.zero,
                    side: BorderSide(color: theme.dividerColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(current, style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_drop_down,
                          size: 16, color: theme.hintColor),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
