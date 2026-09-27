import 'package:flutter/material.dart';

import '../../api/fan_controller.dart';
import '../../app/app_state.dart';

/// One fan: label, live RPM, manual speed slider, "back to auto" affordance.
class FanCard extends StatefulWidget {
  const FanCard({super.key, required this.fan, required this.state});

  final FanInfo fan;
  final AppState state;

  @override
  State<FanCard> createState() => _FanCardState();
}

class _FanCardState extends State<FanCard> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fan = widget.fan;
    final current = _dragValue ?? (fan.speedPercent ?? 0).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(fan.label, style: theme.textTheme.titleMedium),
                ),
                Text(
                  fan.rpm != null ? '${fan.rpm} RPM' : '— RPM',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (fan.canControl)
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: current.clamp(0, 100),
                      min: 0,
                      max: 100,
                      onChanged: (v) => setState(() => _dragValue = v),
                      onChangeEnd: (v) {
                        _dragValue = null;
                        widget.state.setSpeed(fan.id, v.round());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${current.round()}%',
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              )
            else
              Text('Automatic — not controllable',
                  style: theme.textTheme.bodySmall),
            if (fan.canControl && !fan.isAuto)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => widget.state.resetToAuto(fan.id),
                  child: const Text('Back to auto'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
