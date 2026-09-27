import 'package:flutter/material.dart';

/// Windows 11-style pill toggle — hand-built since UI kits are off-limits.
/// On: accent pill, white knob right. Off: bordered pill, grey knob left.
class WinToggle extends StatelessWidget {
  const WinToggle({super.key, required this.value, this.onChanged});

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final enabled = onChanged != null;
    final accent = theme.colorScheme.primary;
    const border = Color(0xFF8A8A8A);

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 40,
          height: 20,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: value && enabled ? accent : Colors.transparent,
            border: Border.all(
              color: value && enabled ? accent : border,
              width: 1,
            ),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: !enabled
                    ? border
                    : value
                        ? theme.colorScheme.onPrimary
                        : border,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
