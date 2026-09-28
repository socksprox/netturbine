import 'package:flutter/material.dart';

import '../theme.dart';

/// One entry in an [NtSelect] flyout: a selectable item, or a divider via
/// [NtSelectDivider].
sealed class NtSelectEntry<T> {
  const NtSelectEntry();
}

class NtSelectItem<T> extends NtSelectEntry<T> {
  const NtSelectItem({required this.value, required this.label, this.icon});

  final T value;
  final String label;

  /// Optional icon shown in the check slot (e.g. "+" for actions). The
  /// selected item always shows a check instead.
  final IconData? icon;
}

class NtSelectDivider<T> extends NtSelectEntry<T> {
  const NtSelectDivider();
}

/// Windows 11-style combo box: a thin bordered button with a chevron that
/// opens a rounded flyout. The current value carries a leading check,
/// items highlight on hover — no Material dropdown chrome.
class NtSelect<T> extends StatelessWidget {
  const NtSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.placeholder,
    this.dense = false,
    this.minMenuWidth = 160,
  });

  /// Current selection. May not match any item — then [placeholder] shows.
  final T? value;
  final List<NtSelectEntry<T>> items;
  final ValueChanged<T> onChanged;

  /// Button label when [value] matches no item.
  final String? placeholder;

  /// Compact variant for inline editors (point rows).
  final bool dense;
  final double minMenuWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final card =
        theme.brightness == Brightness.dark ? NtColors.cardDark : NtColors.cardLight;
    final hoverTint = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.05);

    final label = items
            .whereType<NtSelectItem<T>>()
            .where((i) => i.value == value)
            .firstOrNull
            ?.label ??
        placeholder ??
        '';

    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(card),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(6),
        padding: const WidgetStatePropertyAll(EdgeInsets.all(4)),
        minimumSize: WidgetStatePropertyAll(Size(minMenuWidth, 0)),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: theme.dividerColor),
        )),
      ),
      menuChildren: [
        for (final entry in items)
          switch (entry) {
            NtSelectDivider<T>() => const Divider(height: 8),
            NtSelectItem<T>() => MenuItemButton(
                onPressed: () => onChanged(entry.value),
                style: MenuItemButton.styleFrom(
                  minimumSize: const Size.fromHeight(30),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                  foregroundColor: theme.colorScheme.onSurface,
                  overlayColor: hoverTint,
                  elevation: 0,
                  textStyle: theme.textTheme.bodyMedium,
                ),
                leadingIcon: SizedBox(
                  width: 16,
                  child: entry.value == value
                      ? Icon(Icons.check,
                          size: 14, color: theme.colorScheme.primary)
                      : entry.icon != null
                          ? Icon(entry.icon,
                              size: 14, color: theme.hintColor)
                          : null,
                ),
                child: Text(entry.label),
              ),
          },
      ],
      builder: (context, controller, child) => _ComboButton(
        label: label,
        dense: dense,
        onTap: () =>
            controller.isOpen ? controller.close() : controller.open(),
      ),
    );
  }
}

/// The closed combo box: 1px border, 4px radius, hover tint, label + chevron.
class _ComboButton extends StatefulWidget {
  const _ComboButton(
      {required this.label, required this.dense, required this.onTap});

  final String label;
  final bool dense;
  final VoidCallback onTap;

  @override
  State<_ComboButton> createState() => _ComboButtonState();
}

class _ComboButtonState extends State<_ComboButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final hoverTint = dark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.04);
    final secondary =
        dark ? NtColors.secondaryDark : NtColors.secondaryLight;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          height: widget.dense ? 26 : 30,
          padding: EdgeInsets.symmetric(horizontal: widget.dense ? 6 : 10),
          decoration: BoxDecoration(
            color: _hover ? hoverTint : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.label,
                style: widget.dense
                    ? theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurface)
                    : theme.textTheme.bodyMedium,
              ),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down,
                  size: 14, color: secondary),
            ],
          ),
        ),
      ),
    );
  }
}
