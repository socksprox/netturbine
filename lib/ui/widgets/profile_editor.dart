import 'package:flutter/material.dart';

import '../../api/fan_profile.dart';
import '../../app/app_state.dart';
import 'flyout_select.dart';

/// Curve editor for the active profile: name, driving sensor, and the
/// point list ("at X°C → Y%"). Shown when [FanMode.profile] is selected.
class ProfileEditor extends StatefulWidget {
  const ProfileEditor(
      {super.key, required this.state, required this.profile});

  final AppState state;
  final FanProfile profile;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  static const _maxPoints = 8;
  static final _tempSteps = [for (var t = 30; t <= 100; t += 5) t];

  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.profile.name);
  }

  @override
  void didUpdateWidget(ProfileEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the field in sync when the name changes externally (reset,
    // profile switch). While typing, profile.name mirrors _name so this
    // never clobbers an in-progress edit.
    if (widget.profile.name != _name.text) {
      _name.text = widget.profile.name;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  FanProfile get _profile => widget.profile;

  void _update({String? name, String? sensorId, List<CurvePoint>? points}) {
    widget.state.updateProfile(_profile.copyWith(
        name: name, sensorId: sensorId, points: points));
  }

  void _setPoint(int i, CurvePoint point) {
    final points = _profile.points.toList();
    points[i] = point;
    _update(points: points);
  }

  void _addPoint() {
    final points = _profile.points.toList();
    final last = points.last;
    points.add(CurvePoint(
        temp: (last.temp + 5).clamp(30, 100), percent: last.percent));
    _update(points: points);
  }

  void _removePoint(int i) {
    final points = _profile.points.toList()..removeAt(i);
    _update(points: points);
  }

  void _updateSensor(String id) => _update(sensorId: id);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final profile = _profile;
    final sensors = widget.state.sensors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              style: theme.textTheme.titleMedium,
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                final trimmed = v.trim();
                if (trimmed.isNotEmpty) _update(name: trimmed);
              },
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Text('Sensor', style: theme.textTheme.bodySmall),
                const SizedBox(width: 8),
                if (sensors.isEmpty)
                  Text('No temperature data',
                      style: theme.textTheme.bodySmall)
                else
                  NtSelect<String>(
                    value: profile.sensorId,
                    dense: true,
                    placeholder: profile.sensorId,
                    items: [
                      for (final s in sensors)
                        NtSelectItem(value: s.id, label: s.label),
                    ],
                    onChanged: _updateSensor,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < profile.points.length; i++)
              _PointRow(
                key: ValueKey(i),
                point: profile.points[i],
                tempSteps: _tempSteps,
                canRemove: profile.points.length > 2,
                onChanged: (p) => _setPoint(i, p),
                onRemove: () => _removePoint(i),
              ),
            Row(
              children: [
                TextButton.icon(
                  onPressed: profile.points.length < _maxPoints
                      ? _addPoint
                      : null,
                  icon: const Icon(Icons.add, size: 14),
                  label: const Text('Point'),
                  style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact),
                ),
                const Spacer(),
                if (profile.builtIn && profile.isModified)
                  TextButton(
                    onPressed: () => widget.state.resetProfile(profile.id),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Reset'),
                  ),
                if (!profile.builtIn)
                  TextButton(
                    onPressed: () =>
                        widget.state.deleteProfile(profile.id),
                    style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    child: const Text('Delete'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One curve knot: "at [temp]°C → [−] N% [+] [✕]".
class _PointRow extends StatelessWidget {
  const _PointRow({
    super.key,
    required this.point,
    required this.tempSteps,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final CurvePoint point;
  final List<int> tempSteps;
  final bool canRemove;
  final ValueChanged<CurvePoint> onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text('at', style: theme.textTheme.bodySmall),
          const SizedBox(width: 4),
          NtSelect<int>(
            value: point.temp,
            dense: true,
            minMenuWidth: 72,
            items: [
              for (final t in tempSteps)
                NtSelectItem(value: t, label: '$t'),
            ],
            onChanged: (v) =>
                onChanged(CurvePoint(temp: v, percent: point.percent)),
          ),
          const SizedBox(width: 4),
          Text('°C →', style: theme.textTheme.bodySmall),
          const Spacer(),
          _StepButton(
            icon: Icons.remove,
            onPressed: point.percent > 0
                ? () => onChanged(CurvePoint(
                    temp: point.temp,
                    percent: (point.percent - 5).clamp(0, 100)))
                : null,
          ),
          SizedBox(
            width: 36,
            child: Text('${point.percent}%',
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center),
          ),
          _StepButton(
            icon: Icons.add,
            onPressed: point.percent < 100
                ? () => onChanged(CurvePoint(
                    temp: point.temp,
                    percent: (point.percent + 5).clamp(0, 100)))
                : null,
          ),
          const SizedBox(width: 4),
          _StepButton(
            icon: Icons.close,
            onPressed: canRemove ? onRemove : null,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return SizedBox(
      width: 26,
      height: 26,
      child: IconButton(
        icon: Icon(icon, size: 14),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          splashFactory: NoSplash.splashFactory,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4)),
          foregroundColor: theme.colorScheme.onSurface,
          disabledForegroundColor: theme.hintColor,
          hoverColor: dark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
      ),
    );
  }
}
