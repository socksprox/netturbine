import 'package:flutter/services.dart';

import '../system_integration.dart';

/// SystemIntegration backed by the runner's `netturbine/system`
/// MethodChannel.
///
/// Channel contract (windows/runner/flutter_window.cpp):
///   getLaunchAtStartup()              -> bool
///   setLaunchAtStartup({enabled})     -> bool (success)
///   showWindow()                      -> null
///   quitApp()                         -> null
class WindowsSystemIntegration implements SystemIntegration {
  static const _channel = MethodChannel('netturbine/system');

  @override
  Future<bool> isLaunchAtStartupEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('getLaunchAtStartup') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    try {
      final ok = await _channel
          .invokeMethod<bool>('setLaunchAtStartup', {'enabled': enabled});
      if (ok == false) {
        throw PlatformException(
            code: 'failed', message: 'Could not update the Run key.');
      }
    } on MissingPluginException {
      // Non-Windows host during dev — no-op.
    }
  }

  @override
  Future<void> showWindow() async {
    try {
      await _channel.invokeMethod('showWindow');
    } on MissingPluginException {
      // No-op when the host doesn't implement the channel.
    }
  }

  @override
  Future<void> quitApp() async {
    try {
      await _channel.invokeMethod('quitApp');
    } on MissingPluginException {
      // No-op when the host doesn't implement the channel.
    }
  }
}
