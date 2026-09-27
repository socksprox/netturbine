import 'dart:async';

import 'fan_controller.dart';
import 'system_integration.dart';

/// Fallback used on platforms with no fan backend. Reports zero fans and
/// no capabilities; control calls throw [FanControlException].
class UnsupportedFanController implements FanController {
  final _stream = StreamController<List<FanInfo>>.broadcast();

  UnsupportedFanController() {
    scheduleMicrotask(() {
      if (!_stream.isClosed) _stream.add(const []);
    });
  }

  @override
  List<FanInfo> get fans => const [];

  @override
  Stream<List<FanInfo>> get fanStream => _stream.stream;

  @override
  FanCapabilities get capabilities => FanCapabilities.none;

  @override
  Future<void> setSpeed(String fanId, int percent) =>
      throw const FanControlException(
          'Fan control is not supported on this platform.');

  @override
  Future<void> resetToAuto(String fanId) =>
      throw const FanControlException(
          'Fan control is not supported on this platform.');

  @override
  Future<void> dispose() => _stream.close();
}

/// Fallback used on platforms with no OS-integration impl. All calls are
/// safe no-ops so the UI stays functional.
class UnsupportedSystemIntegration implements SystemIntegration {
  @override
  Future<bool> isLaunchAtStartupEnabled() async => false;

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {}

  @override
  Future<void> showWindow() async {}

  @override
  Future<void> quitApp() async {}
}
