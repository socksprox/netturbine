// This file is the api/ layer's single exception to the "no dart:io" rule:
// platform detection has to happen somewhere, and it happens exactly here.
import 'dart:io' show Platform;

import 'fan_controller.dart';
import 'system_integration.dart';
import 'unsupported.dart';
import 'windows/windows_fan_controller.dart';
import 'windows/windows_system_integration.dart';

/// Selects the concrete backend for the running OS.
/// Add `Platform.isMacOS` (etc.) branches here when a new impl lands.
FanController createPlatformFanController() {
  if (Platform.isWindows) return WindowsFanController();
  return UnsupportedFanController();
}

SystemIntegration createPlatformSystemIntegration() {
  if (Platform.isWindows) return WindowsSystemIntegration();
  return UnsupportedSystemIntegration();
}
