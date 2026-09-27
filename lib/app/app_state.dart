import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/fan_controller.dart';
import '../api/system_integration.dart';

/// App state: fan snapshots, launch-at-startup setting, and the temporary
/// boost timer. Widgets read this; the platform boundary stays behind
/// [FanController] and [SystemIntegration].
class AppState extends ChangeNotifier {
  AppState({required this.fan, required this.system});

  static const boostDuration = Duration(minutes: 15);
  static const _boostTick = Duration(seconds: 1);

  final FanController fan;
  final SystemIntegration system;
  StreamSubscription<List<FanInfo>>? _sub;

  List<FanInfo> fans = const [];
  bool launchAtStartup = false;
  bool backendError = false;

  Timer? _boostTimer;
  Duration? _boostRemaining;

  FanCapabilities get capabilities => fan.capabilities;
  bool get isBoosting => _boostRemaining != null;
  Duration? get boostRemaining => _boostRemaining;

  /// Call once at startup; safe to call before runApp.
  Future<void> init() async {
    _sub = fan.fanStream.listen((snapshot) {
      fans = snapshot;
      notifyListeners();
    }, onError: (_) {
      backendError = true;
      notifyListeners();
    });
    launchAtStartup = await system.isLaunchAtStartupEnabled();
    notifyListeners();
  }

  Future<void> setSpeed(String fanId, int percent) async {
    try {
      backendError = false;
      await fan.setSpeed(fanId, percent);
    } on FanControlException {
      backendError = true;
    }
    notifyListeners();
  }

  Future<void> resetToAuto(String fanId) async {
    try {
      backendError = false;
      await fan.resetToAuto(fanId);
    } on FanControlException {
      backendError = true;
    }
    notifyListeners();
  }

  /// Sets every controllable fan to 100% for [duration], then resets them
  /// all to automatic control.
  Future<void> startBoost([Duration duration = boostDuration]) async {
    _boostTimer?.cancel();
    try {
      backendError = false;
      for (final f in fans.where((f) => f.canControl)) {
        await fan.setSpeed(f.id, 100);
      }
      _boostRemaining = duration;
      _boostTimer = Timer.periodic(_boostTick, (_) => _tickBoost());
    } on FanControlException {
      backendError = true;
      _boostRemaining = null;
    }
    notifyListeners();
  }

  Future<void> cancelBoost() => _endBoost();

  void _tickBoost() {
    final remaining = _boostRemaining;
    if (remaining == null) return;
    final next = remaining - _boostTick;
    if (next <= Duration.zero) {
      unawaited(_endBoost());
    } else {
      _boostRemaining = next;
      notifyListeners();
    }
  }

  Future<void> _endBoost() async {
    _boostTimer?.cancel();
    _boostTimer = null;
    _boostRemaining = null;
    try {
      for (final f in fans.where((f) => f.canControl)) {
        await fan.resetToAuto(f.id);
      }
    } on FanControlException {
      backendError = true;
    }
    notifyListeners();
  }

  Future<void> setLaunchAtStartup(bool enabled) async {
    launchAtStartup = enabled;
    notifyListeners();
    try {
      await system.setLaunchAtStartup(enabled);
    } catch (_) {
      launchAtStartup = !enabled;
      notifyListeners();
    }
  }

  Future<void> showWindow() => system.showWindow();
  Future<void> quitApp() => system.quitApp();

  @override
  void dispose() {
    _boostTimer?.cancel();
    unawaited(_sub?.cancel() ?? Future.value());
    super.dispose();
  }
}
