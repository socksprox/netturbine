import 'fan_controller.dart';
import 'system_integration.dart';
import 'unsupported.dart';

/// Fallback selector for platforms without `dart:io` (e.g. web).
FanController createPlatformFanController() => UnsupportedFanController();

SystemIntegration createPlatformSystemIntegration() =>
    UnsupportedSystemIntegration();
