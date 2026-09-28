import 'package:flutter/material.dart';

import '../../api/fan_controller.dart';
import '../../app/app_state.dart';

/// One fan: label, live RPM/duty readout, and a speed slider — editable
/// in Fixed mode, a read-only gauge in Auto/Profile mode and during boost.
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
    final state = widget.state;
    final interactive = fan.canControl &&
        state.fanMode == FanMode.fixed &&
        !state.isBoosting;

    // The slider is a setpoint control: bind it to the requested speed,
    // not speedPercent. The measured duty ramps toward the setpoint over
    // seconds (and firmware can clamp it), so showing it here makes the
    // slider appear to bounce back right after release.
    final target = fan.isAuto ? null : state.manualTarget(fan.id);
    final measured = (fan.speedPercent ?? 0).toDouble();
    final current = interactive
        ? (_dragValue ?? target?.toDouble() ?? measured)
        : measured;

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
                  fan.rpm != null
                      ? '${fan.rpm} RPM'
                      : fan.speedPercent != null
                          ? 'at ${fan.speedPercent}%'
                          : '— RPM',
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
                      value: current.clamp(0.0, 100.0),
                      min: 0,
                      max: 100,
                      onChanged: interactive
                          ? (v) => setState(() => _dragValue = v)
                          : null,
                      onChangeEnd: interactive
                          ? (v) {
                              _dragValue = null;
                              state.setSpeed(fan.id, v.round());
                            }
                          : null,
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
            if (interactive && !fan.isAuto)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => state.resetToAuto(fan.id),
                  child: const Text('Back to auto'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
