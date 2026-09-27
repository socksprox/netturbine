import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

/// One item in a [SegmentedSelector].
class SegmentOption<T> {
  const SegmentOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Windows 11-style segmented switcher — a pill track with a sliding
/// indicator, press-scale feedback, drag-to-select, and arrow-key navigation.
/// Ported from shadowfly-app's SegmentedSelector.
class SegmentedSelector<T> extends StatefulWidget {
  const SegmentedSelector({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 32,
  });

  final List<SegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  State<SegmentedSelector<T>> createState() => _SegmentedSelectorState<T>();
}

class _SegmentedSelectorState<T> extends State<SegmentedSelector<T>>
    with TickerProviderStateMixin {
  late AnimationController _positionController;
  late AnimationController _scaleController;
  late Animation<double> _scaleAnimation;
  late List<FocusNode> _segmentFocusNodes;

  double _tabWidth = 1.0;
  double _dragStartX = 0.0;
  double _dragStartValue = 0.0;

  @override
  void initState() {
    super.initState();
    _segmentFocusNodes = List.generate(
      widget.options.length,
      (i) => FocusNode(debugLabel: 'segment_$i'),
    );
    final initialIndex = widget.options.indexWhere(
      (option) => option.value == widget.selected,
    );
    final initial = (initialIndex >= 0 ? initialIndex : 0).toDouble();

    _positionController = AnimationController(
      vsync: this,
      value: initial,
      lowerBound: 0.0,
      upperBound: widget.options.length > 1
          ? (widget.options.length - 1).toDouble()
          : 1.0,
    );

    _scaleController = AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(SegmentedSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newIndex = widget.options.indexWhere(
      (option) => option.value == widget.selected,
    );
    if (newIndex >= 0 &&
        (newIndex.toDouble() - _positionController.value).abs() > 0.01) {
      _positionController.animateTo(
        newIndex.toDouble(),
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    for (final node in _segmentFocusNodes) {
      node.dispose();
    }
    _positionController.dispose();
    _scaleController.dispose();
    super.dispose();
  }

  void _selectIndex(int index) {
    _positionController.animateTo(
      index.toDouble(),
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
    widget.onChanged(widget.options[index].value);
  }

  void _onDragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartValue = _positionController.value;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final dx = details.localPosition.dx - _dragStartX;
    _positionController.value = (_dragStartValue + dx / _tabWidth).clamp(
      0.0,
      (widget.options.length - 1).toDouble(),
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final nearest = _positionController.value.round().clamp(
      0,
      widget.options.length - 1,
    );
    _positionController.animateTo(
      nearest.toDouble(),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
    widget.onChanged(widget.options[nearest].value);
  }

  KeyEventResult _handleKeyEvent(KeyEvent event, int index) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        if (index > 0) {
          _selectIndex(index - 1);
          _segmentFocusNodes[index - 1].requestFocus();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        if (index < widget.options.length - 1) {
          _selectIndex(index + 1);
          _segmentFocusNodes[index + 1].requestFocus();
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
      case LogicalKeyboardKey.space:
        _selectIndex(index);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final border = dark ? NtColors.borderDark : NtColors.borderLight;
    final track = dark ? const Color(0xFF282828) : const Color(0xFFEFEFEF);
    final active = dark ? const Color(0xFF3A3A3A) : Colors.white;
    final secondary = dark ? NtColors.secondaryDark : NtColors.secondaryLight;

    return AnimatedBuilder(
      animation: _positionController,
      builder: (context, child) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = constraints.maxWidth / widget.options.length;
            _tabWidth = tabWidth;
            final animValue = _positionController.value;
            final indicatorOffset = animValue * tabWidth;

            return GestureDetector(
              onHorizontalDragStart: _onDragStart,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: Container(
                height: widget.height,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      left: indicatorOffset + 3,
                      top: 3,
                      bottom: 3,
                      width: tabWidth - 6,
                      child: AnimatedBuilder(
                        animation: _scaleAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: _scaleAnimation.value,
                            child: Container(
                              decoration: BoxDecoration(
                                color: active,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: border),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    Row(
                      children: List.generate(widget.options.length, (index) {
                        final tabItem = widget.options[index];
                        final isSelected = (animValue - index).abs() < 0.5;

                        return Expanded(
                          child: Focus(
                            focusNode: _segmentFocusNodes[index],
                            onKeyEvent: (node, event) =>
                                _handleKeyEvent(event, index),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTapDown: (_) {
                                  _segmentFocusNodes[index].requestFocus();
                                  _selectIndex(index);
                                  _scaleController.forward();
                                },
                                onTapUp: (_) => _scaleController.reverse(),
                                onTapCancel: () => _scaleController.reverse(),
                                child: SizedBox(
                                  height: widget.height,
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      if (tabItem.icon != null) ...[
                                        Icon(
                                          tabItem.icon!,
                                          size: 14,
                                          color: isSelected
                                              ? cs.primary
                                              : secondary,
                                        ),
                                        const SizedBox(width: 5),
                                      ],
                                      Text(
                                        tabItem.label,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                          fontWeight: isSelected
                                              ? FontWeight.w600
                                              : FontWeight.w400,
                                          color: isSelected
                                              ? cs.onSurface
                                              : secondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
