import 'package:flutter/material.dart';

import '../../app/app_state.dart';

/// "Max speed for 15 min" — runs all controllable fans at 100%, then resets
/// them to auto. Shows a countdown while active.
class BoostButton extends StatelessWidget {
  const BoostButton({super.key, required this.state});

  final AppState state;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canBoost = state.capabilities.canSetSpeed &&
        state.fans.any((f) => f.canControl);

    if (state.isBoosting) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.wind_power,
                  size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Boosting · ${_fmt(state.boostRemaining ?? Duration.zero)} left',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              TextButton(
                onPressed: state.cancelBoost,
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: canBoost ? () => state.startBoost() : null,
        child: Text(
            'Max speed for ${AppState.boostDuration.inMinutes} min'),
      ),
    );
  }
}
