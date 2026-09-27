import 'package:flutter/material.dart';

import '../theme.dart';

/// Windows 11-style segmented control — a pill track with items that get an
/// elevated surface when selected. Used for the top-level page switcher.
class SegmentedTabs extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  final List<String> items;
  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final border = dark ? NtColors.borderDark : NtColors.borderLight;
    final track = dark ? const Color(0xFF282828) : const Color(0xFFEFEFEF);
    final active = dark ? const Color(0xFF3A3A3A) : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: track,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  decoration: BoxDecoration(
                    color: i == selected ? active : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: i == selected
                        ? Border.all(color: border)
                        : const Border(),
                  ),
                  child: Text(
                    items[i],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight:
                          i == selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
