import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../api/fan_controller.dart';
import '../api/fan_profile.dart';
import '../api/system_integration.dart';

/// How fan speed is driven.
enum FanMode {
  /// Firmware controls the fans — the app only displays, never writes.
  auto,

  /// A constant per-fan percent set by the manual sliders.
  fixed,

  /// A [FanProfile] temperature curve evaluated on every poll.
  profile,
}

/// App state: fan snapshots, control mode + profiles, launch-at-startup
/// setting, and the temporary boost timer. Widgets read this; the platform
/// boundary stays behind [FanController] and [SystemIntegration].
class AppState extends ChangeNotifier {
  AppState({required this.fan, required this.system});

  static const boostDuration = Duration(minutes: 15);
  static const _boostTick = Duration(seconds: 1);

  /// Minimum change in curve output before rewriting the EC — avoids
  /// spamming writes on 1% wobble as the temperature jitters.
  static const _curveHysteresis = 2;

  final FanController fan;
  final SystemIntegration system;
  StreamSubscription<List<FanInfo>>? _sub;

  List<FanInfo> fans = const [];
  List<TempSensor> sensors = const [];
  bool launchAtStartup = false;
  bool backendError = false;

  FanMode fanMode = FanMode.auto;
  List<FanProfile> profiles = FanProfile.builtInProfiles;
  String? activeProfileId;

  /// Last speed requested per fan via setSpeed/boost/curve, valid while
  /// that fan reports manual mode. `FanInfo.speedPercent` is the measured
  /// duty — firmware ramps toward the setpoint over seconds and can clamp
  /// it — so the UI binds its slider to this target instead.
  final _manualTargets = <String, int>{};

  bool _settingsLoaded = false;
  bool _modeApplied = false;
  bool _curveBusy = false;
  bool _curveHolding = false;
  int? _lastCurvePercent;

  Timer? _boostTimer;
  Duration? _boostRemaining;

  FanCapabilities get capabilities => fan.capabilities;
  bool get isBoosting => _boostRemaining != null;
  Duration? get boostRemaining => _boostRemaining;

  /// The currently selected profile, or null in auto/fixed mode.
  FanProfile? get activeProfile =>
      profiles.where((p) => p.id == activeProfileId).firstOrNull;

  /// Last requested manual speed for [fanId], or null when that fan is on
  /// automatic control or no override has been made this session.
  int? manualTarget(String fanId) => _manualTargets[fanId];

  /// Call once at startup; safe to call before runApp.
  Future<void> init() async {
    _sub = fan.fanStream.listen((snapshot) {
      fans = snapshot;
      sensors = fan.sensors;
      if (_settingsLoaded && !_modeApplied) {
        // First snapshot after settings load — apply the persisted mode.
        _modeApplied = true;
        unawaited(_applyMode());
      } else if (_modeApplied) {
        unawaited(_applyCurve());
      }
      notifyListeners();
    }, onError: (_) {
      backendError = true;
      notifyListeners();
    });
    launchAtStartup = await system.isLaunchAtStartupEnabled();
    await _loadSettings();
    notifyListeners();
  }

  // ------------------------------------------------------------ modes

  /// Firmware takes over; all manual holds are released.
  Future<void> selectAuto() async {
    if (fanMode == FanMode.auto) return;
    fanMode = FanMode.auto;
    activeProfileId = null;
    backendError = false;
    await _applyMode();
    notifyListeners();
    unawaited(_persist());
  }

  /// Constant per-fan percent via the sliders. Switching in holds the
  /// current measured speed so nothing jumps.
  Future<void> selectFixed() async {
    if (fanMode == FanMode.fixed) return;
    fanMode = FanMode.fixed;
    activeProfileId = null;
    backendError = false;
    for (final f in fans.where((f) => f.canControl)) {
      _manualTargets[f.id] ??= f.speedPercent ?? 50;
    }
    await _applyMode();
    notifyListeners();
    unawaited(_persist());
  }

  /// Temperature curve mode. [id] must exist in [profiles].
  Future<void> selectProfile(String id) async {
    if (!profiles.any((p) => p.id == id)) return;
    fanMode = FanMode.profile;
    activeProfileId = id;
    _lastCurvePercent = null;
    backendError = false;
    await _applyMode();
    notifyListeners();
    unawaited(_persist());
  }

  /// Applies the current mode to the hardware: release holds, re-write
  /// fixed targets, or run one curve evaluation.
  Future<void> _applyMode() async {
    try {
      switch (fanMode) {
        case FanMode.auto:
          _manualTargets.clear();
          _curveHolding = false;
          _lastCurvePercent = null;
          for (final f in fans.where((f) => f.canControl)) {
            await fan.resetToAuto(f.id);
          }
        case FanMode.fixed:
          _curveHolding = false;
          _lastCurvePercent = null;
          for (final f in fans.where(
              (f) => f.canControl && _manualTargets.containsKey(f.id))) {
            await fan.setSpeed(f.id, _manualTargets[f.id]!);
          }
        case FanMode.profile:
          _lastCurvePercent = null;  // force a write — e.g. post-boost the
          await _applyCurve();       // EC holds 100% but the curve value didn't move
      }
    } on FanControlException {
      backendError = true;
    }
  }

  /// One profile-mode tick: read the driving sensor, interpolate the
  /// target, and write it to every controllable fan when it moved past
  /// the hysteresis band. A missing reading releases fans to firmware —
  /// safer than holding a stale setpoint.
  Future<void> _applyCurve() async {
    if (fanMode != FanMode.profile || isBoosting || _curveBusy) return;
    final profile = activeProfile;
    if (profile == null) return;
    _curveBusy = true;
    try {
      final celsius = sensors
          .where((s) => s.id == profile.sensorId)
          .firstOrNull
          ?.celsius;
      final target = profile.speedFor(celsius);
      if (target == null) {
        if (_curveHolding) {
          _curveHolding = false;
          _lastCurvePercent = null;
          for (final f in fans.where((f) => f.canControl)) {
            await fan.resetToAuto(f.id);
            _manualTargets.remove(f.id);
          }
        }
        return;
      }
      // Skip the write when the target barely moved — unless a
      // controllable fan fell back to auto (helper restart, firmware
      // reclaim), in which case re-assert the setpoint.
      final anyUnheld = fans.any((f) => f.canControl && f.isAuto);
      if (!anyUnheld &&
          _lastCurvePercent != null &&
          (target - _lastCurvePercent!).abs() < _curveHysteresis) {
        return;
      }
      for (final f in fans.where((f) => f.canControl)) {
        await fan.setSpeed(f.id, target);
        _manualTargets[f.id] = target;
      }
      _curveHolding = true;
      _lastCurvePercent = target;
      notifyListeners();
    } on FanControlException {
      backendError = true;
    } finally {
      _curveBusy = false;
    }
  }

  // --------------------------------------------------------- profiles

  /// Replaces the profile with the same id. Re-evaluates the curve when
  /// the active profile's sensor or points changed.
  void updateProfile(FanProfile updated) {
    final old = profiles.where((p) => p.id == updated.id).firstOrNull;
    if (old == null) return;
    profiles = [for (final p in profiles) p.id == updated.id ? updated : p];
    if (updated.id == activeProfileId && !old.curveSameAs(updated)) {
      _lastCurvePercent = null;
      unawaited(_applyCurve());
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// Duplicates the active profile (or Balanced) into a new custom
  /// profile and selects it.
  Future<void> duplicateProfile() async {
    final source = activeProfile ?? FanProfile.factoryVersion('balanced')!;
    final copy = FanProfile(
      id: 'custom-${DateTime.now().millisecondsSinceEpoch}',
      name: '${source.name} copy',
      sensorId: source.sensorId,
      points: source.points.toList(),
    );
    profiles = [...profiles, copy];
    await selectProfile(copy.id);
  }

  /// Deletes a custom profile. Built-ins can't be deleted — only reset.
  Future<void> deleteProfile(String id) async {
    final p = profiles.where((e) => e.id == id).firstOrNull;
    if (p == null || p.builtIn) return;
    profiles = profiles.where((e) => e.id != id).toList();
    if (activeProfileId == id) {
      fanMode = FanMode.auto;
      activeProfileId = null;
      await _applyMode();
    }
    notifyListeners();
    unawaited(_persist());
  }

  /// Restores a built-in profile to its shipped curve.
  void resetProfile(String id) {
    final factory = FanProfile.factoryVersion(id);
    if (factory != null) updateProfile(factory);
  }

  // ------------------------------------------------------ manual mode

  Future<void> setSpeed(String fanId, int percent) async {
    try {
      backendError = false;
      await fan.setSpeed(fanId, percent);
      _manualTargets[fanId] = percent;
    } on FanControlException {
      backendError = true;
    }
    notifyListeners();
  }

  Future<void> resetToAuto(String fanId) async {
    try {
      backendError = false;
      await fan.resetToAuto(fanId);
      _manualTargets.remove(fanId);
    } on FanControlException {
      backendError = true;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ boost

  /// Sets every controllable fan to 100% for [duration], then returns to
  /// whatever mode was active before.
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
    backendError = false;
    await _applyMode();
    notifyListeners();
  }

  // ---------------------------------------------------------- startup

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

  // ------------------------------------------------------- persistence

  Future<void> _persist() =>
      system.saveSettings(jsonEncode({
        'mode': fanMode.name,
        'profile': activeProfileId,
        'fixed': _manualTargets,
        'profiles': [for (final p in profiles) p.toJson()],
      }));

  Future<void> _loadSettings() async {
    try {
      final raw = await system.loadSettings();
      if (raw != null) {
        final json = jsonDecode(raw);
        if (json is Map) {
          _applySettings(json);
        }
      }
    } catch (_) {
      // Corrupt or incompatible settings file — fall back to defaults.
    }
    _settingsLoaded = true;
  }

  void _applySettings(Map<dynamic, dynamic> json) {
    final rawProfiles = json['profiles'];
    if (rawProfiles is List) {
      final loaded = <FanProfile>[
        for (final e in rawProfiles)
          if (e is Map)
            ?FanProfile.fromJson(Map<String, dynamic>.from(e)),
      ];
      // Built-ins keep their canonical order; customs follow. Any
      // built-in missing from the file (older version) gets its factory.
      profiles = [
        for (final b in FanProfile.builtInProfiles)
          loaded.firstWhere((p) => p.id == b.id, orElse: () => b),
        ...loaded.where((p) => !p.builtIn),
      ];
    }
    final fixed = json['fixed'];
    if (fixed is Map) {
      for (final e in fixed.entries) {
        if (e.key is String && e.value is num) {
          _manualTargets[e.key as String] =
              (e.value as num).round().clamp(0, 100);
        }
      }
    }
    final profile = json['profile'];
    if (profile is String && profiles.any((p) => p.id == profile)) {
      activeProfileId = profile;
    }
    fanMode = switch (json['mode']) {
      'fixed' => FanMode.fixed,
      'profile' when activeProfileId != null => FanMode.profile,
      _ => FanMode.auto,
    };
  }

  @override
  void dispose() {
    _boostTimer?.cancel();
    unawaited(_sub?.cancel() ?? Future.value());
    super.dispose();
  }
}
