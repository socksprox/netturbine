import 'dart:async';

import 'package:netturbine/api/fan_controller.dart';
import 'package:netturbine/api/system_integration.dart';

/// In-memory FanController for tests. Never touches hardware, registry, or
/// WMI. Call [emit] after mutating [fans] to push a snapshot.
class FakeFanController implements FanController {
  FakeFanController({this.fans = const [], this.capabilities = _all});

  static const _all = FanCapabilities(canReadRpm: true, canSetSpeed: true);

  final _stream = StreamController<List<FanInfo>>.broadcast();
  final Map<String, int> speeds = {};
  final List<String> resetCalls = [];
  bool throwOnControl = false;
  bool disposed = false;

  @override
  List<FanInfo> fans;

  @override
  List<TempSensor> sensors = const [];

  @override
  FanCapabilities capabilities;

  void emit() => _stream.add(fans);

  @override
  Stream<List<FanInfo>> get fanStream => _stream.stream;

  @override
  Future<void> setSpeed(String fanId, int percent) async {
    if (throwOnControl) throw const FanControlException('test failure');
    speeds[fanId] = percent;
    fans = [
      for (final f in fans)
        f.id == fanId
            ? FanInfo(
                id: f.id,
                label: f.label,
                rpm: percent * 30,
                speedPercent: percent,
                canControl: f.canControl,
                isAuto: false,
              )
            : f,
    ];
  }

  @override
  Future<void> resetToAuto(String fanId) async {
    if (throwOnControl) throw const FanControlException('test failure');
    resetCalls.add(fanId);
    fans = [
      for (final f in fans)
        f.id == fanId
            ? FanInfo(
                id: f.id,
                label: f.label,
                rpm: f.rpm,
                speedPercent: f.speedPercent,
                canControl: f.canControl,
                isAuto: true,
              )
            : f,
    ];
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _stream.close();
  }
}

/// In-memory SystemIntegration for tests.
class FakeSystemIntegration implements SystemIntegration {
  bool launchAtStartup = false;
  bool setStartupShouldThrow = false;
  int showWindowCalls = 0;
  int quitCalls = 0;

  @override
  Future<bool> isLaunchAtStartupEnabled() async => launchAtStartup;

  @override
  Future<void> setLaunchAtStartup(bool enabled) async {
    if (setStartupShouldThrow) throw Exception('registry write failed');
    launchAtStartup = enabled;
  }

  @override
  Future<void> showWindow() async => showWindowCalls++;

  @override
  Future<void> quitApp() async => quitCalls++;
}
