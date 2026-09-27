import 'dart:async';

import '../fan_controller.dart';

class _SimFan {
  _SimFan({required this.id, required this.label, required this.basePercent});

  final String id;
  final String label;
  final int basePercent;

  bool auto = true;
  int percent = 0;
  int drift = 0;
}

/// In-memory fan backend for development. Two fake fans whose RPM ramps
/// toward speed percent; in auto mode the target drifts to simulate load.
///
/// Enabled with `--dart-define=NETTURBINE_SIMULATE=true` — see main.dart.
class SimulatedFanController implements FanController {
  static const _pollInterval = Duration(milliseconds: 500);

  final _stream = StreamController<List<FanInfo>>.broadcast();
  Timer? _pollTimer;
  int _tick = 0;

  final _fans = <_SimFan>[
    _SimFan(id: 'cpu', label: 'CPU Fan', basePercent: 35),
    _SimFan(id: 'gpu', label: 'GPU Fan', basePercent: 28),
  ]..forEach((f) => f.percent = f.basePercent);

  SimulatedFanController() {
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
    _poll();
  }

  void _poll() {
    _tick++;
    for (final f in _fans) {
      if (f.auto) {
        // Slow drift around the base speed to simulate changing load.
        f.drift = ((_tick * (f.id == 'cpu' ? 3 : 5)) % 40) - 20;
        f.percent = (f.basePercent + f.drift).clamp(10, 90);
      }
    }
    if (!_stream.isClosed) _stream.add(fans);
  }

  @override
  List<FanInfo> get fans => [
        for (final f in _fans)
          FanInfo(
            id: f.id,
            label: f.label,
            rpm: f.percent * 32,
            speedPercent: f.percent,
            canControl: true,
            isAuto: f.auto,
          ),
      ];

  @override
  Stream<List<FanInfo>> get fanStream => _stream.stream;

  @override
  FanCapabilities get capabilities =>
      const FanCapabilities(canReadRpm: true, canSetSpeed: true);

  @override
  List<TempSensor> get sensors => [
        // Simulated CPU temp: warmer when fans are pushed, with slow drift.
        TempSensor(
          id: 'cpu',
          label: 'CPU',
          celsius: 42 + ((_tick * 2) % 30) ~/ 3 +
              (_fans.first.percent - _fans.first.basePercent) ~/ 5,
        ),
      ];

  @override
  Future<void> setSpeed(String fanId, int percent) async {
    final f = _fans.firstWhere((f) => f.id == fanId,
        orElse: () =>
            throw FanControlException('Unknown fan: $fanId'));
    f.auto = false;
    f.percent = percent.clamp(0, 100);
    _poll();
  }

  @override
  Future<void> resetToAuto(String fanId) async {
    final f = _fans.firstWhere((f) => f.id == fanId,
        orElse: () =>
            throw FanControlException('Unknown fan: $fanId'));
    f.auto = true;
    _poll();
  }

  @override
  Future<void> dispose() async {
    _pollTimer?.cancel();
    await _stream.close();
  }
}
