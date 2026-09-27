import 'dart:async';

import 'package:flutter/material.dart';

import 'api/fan_controller.dart';
import 'api/simulated/simulated_fan_controller.dart';
import 'api/system_integration.dart';
import 'app/app_state.dart';
import 'ui/app.dart';

/// Run with `--dart-define=NETTURBINE_SIMULATE=true` to use fake fans
/// instead of the (possibly unavailable) hardware backend.
const bool _simulate = bool.fromEnvironment('NETTURBINE_SIMULATE');

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  final FanController fanController = _simulate
      ? SimulatedFanController()
      : FanController.forCurrentPlatform();
  final state = AppState(
    fan: fanController,
    system: SystemIntegration.forCurrentPlatform(),
  );
  unawaited(state.init());

  runApp(NetturbineApp(state: state));
}
