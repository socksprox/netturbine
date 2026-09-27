import 'dart:async';

import 'package:flutter/services.dart';

import '../fan_controller.dart';

/// FanController backed by the Windows runner's `netturbine/fan`
/// MethodChannel.
///
/// Channel contract (implemented in windows/runner/flutter_window.cpp):
///   getFans()             -> {capabilities: {canReadRpm, canSetSpeed},
///                             fans: [{id, label, rpm, speedPercent, canControl}]}
///   setSpeed(fanId, percent)   -> null
///   resetToAuto(fanId)         -> null
///
/// The runner proxies to the elevated NetturbineFanHelper service over
/// \\.\pipe\netturbine_fan (EC registers via PawnIO). When the helper is not
/// installed or running the channel reports zero fans and the UI disables its
/// controls accordingly.
class WindowsFanController implements FanController {
  static const _channel = MethodChannel('netturbine/fan');
  static const _pollInterval = Duration(seconds: 2);

  final _stream = StreamController<List<FanInfo>>.broadcast();
  Timer? _pollTimer;
  List<FanInfo> _fans = const [];
  List<TempSensor> _sensors = const [];
  FanCapabilities _capabilities = FanCapabilities.none;

  WindowsFanController() {
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    unawaited(_poll());
  }

  Future<void> _poll() async {
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('getFans');
      if (result != null) {
        _capabilities = _parseCapabilities(result['capabilities']);
        _fans = [
          for (final f in (result['fans'] as List? ?? const [])) _parseFan(f),
        ];
        _sensors = [
          for (final s in (result['temps'] as List? ?? const []))
            _parseSensor(s),
        ];
      }
    } on MissingPluginException {
      _fans = const [];
      _sensors = const [];
      _capabilities = FanCapabilities.none;
    } on PlatformException {
      // Backend transiently unavailable — keep last known snapshot.
    }
    if (!_stream.isClosed) _stream.add(_fans);
  }

  @override
  List<FanInfo> get fans => _fans;

  @override
  Stream<List<FanInfo>> get fanStream => _stream.stream;

  @override
  FanCapabilities get capabilities => _capabilities;

  @override
  List<TempSensor> get sensors => _sensors;

  @override
  Future<void> setSpeed(String fanId, int percent) async {
    try {
      await _channel
          .invokeMethod('setSpeed', {'fanId': fanId, 'percent': percent});
    } on PlatformException catch (e) {
      throw FanControlException(e.message ?? 'setSpeed failed');
    } on MissingPluginException {
      throw const FanControlException('Fan backend unavailable.');
    }
    unawaited(_poll());
  }

  @override
  Future<void> resetToAuto(String fanId) async {
    try {
      await _channel.invokeMethod('resetToAuto', {'fanId': fanId});
    } on PlatformException catch (e) {
      throw FanControlException(e.message ?? 'resetToAuto failed');
    } on MissingPluginException {
      throw const FanControlException('Fan backend unavailable.');
    }
    unawaited(_poll());
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    await _stream.close();
  }

  static FanCapabilities _parseCapabilities(dynamic raw) {
    if (raw is! Map) return FanCapabilities.none;
    return FanCapabilities(
      canReadRpm: raw['canReadRpm'] == true,
      canSetSpeed: raw['canSetSpeed'] == true,
    );
  }

  static TempSensor _parseSensor(dynamic raw) {
    final map = raw as Map;
    return TempSensor(
      id: map['id'] as String,
      label: map['label'] as String? ?? map['id'] as String,
      celsius: map['celsius'] as int?,
    );
  }

  static FanInfo _parseFan(dynamic raw) {
    final map = raw as Map;
    return FanInfo(
      id: map['id'] as String,
      label: map['label'] as String? ?? map['id'] as String,
      rpm: map['rpm'] as int?,
      speedPercent: map['speedPercent'] as int?,
      canControl: map['canControl'] == true,
      isAuto: map['isAuto'] != false,
    );
  }
}
