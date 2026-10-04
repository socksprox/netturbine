import 'package:flutter/material.dart';

/// Windows 11-style title-bar pin toggle: keeps the flyout open on blur.
/// Outlined pin when off; accent pin on a tinted chip when on.
class PinButton extends StatefulWidget {
  const PinButton({super.key, required this.pinned, required this.onChanged});

  final bool pinned;
  final ValueChanged<bool> onChanged;

  @override
  State<PinButton> createState() => _PinButtonState();
}

class _PinButtonState extends State<PinButton> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final fg = widget.pinned
        ? accent
        : theme.textTheme.bodySmall?.color ?? theme.hintColor;

    return Tooltip(
      message: widget.pinned ? 'Unpin window' : 'Keep window open',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovering = true),
        onExit: (_) => setState(() => _hovering = false),
        child: GestureDetector(
          onTap: () => widget.onChanged(!widget.pinned),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 100),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              color: widget.pinned
                  ? accent.withValues(alpha: _hovering ? 0.2 : 0.12)
                  : _hovering
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.06)
                      : Colors.transparent,
            ),
            child: Icon(
              widget.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 15,
              color: fg,
            ),
          ),
        ),
      ),
    );
  }
}
