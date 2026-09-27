import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netturbine/api/fan_controller.dart';
import 'package:netturbine/app/app_state.dart';

import '../fakes.dart';

const _cpu = FanInfo(
    id: 'cpu',
    label: 'CPU Fan',
    rpm: 1200,
    speedPercent: 40,
    canControl: true);

void main() {
  test('init loads launch-at-startup and subscribes to fans', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final system = FakeSystemIntegration()..launchAtStartup = true;
      final state = AppState(fan: fan, system: system);
      state.init();
      async.flushMicrotasks();
      expect(state.launchAtStartup, isTrue);
      fan.emit();
      async.flushMicrotasks();
      expect(state.fans, hasLength(1));
      state.dispose();
    });
  });

  test('boost sets all controllable fans to 100% then resets to auto', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.startBoost();
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 100);
      expect(state.isBoosting, isTrue);

      async.elapse(AppState.boostDuration);
      async.flushMicrotasks();
      expect(state.isBoosting, isFalse);
      expect(fan.resetCalls, contains('cpu'));
      state.dispose();
    });
  });

  test('cancelBoost resets fans immediately', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.startBoost();
      async.flushMicrotasks();
      state.cancelBoost();
      async.flushMicrotasks();
      expect(state.isBoosting, isFalse);
      expect(fan.resetCalls, contains('cpu'));
      state.dispose();
    });
  });

  test('setLaunchAtStartup reverts when the OS write fails', () {
    fakeAsync((async) {
      final system = FakeSystemIntegration()..setStartupShouldThrow = true;
      final state = AppState(
          fan: FakeFanController(), system: system);
      state.init();
      async.flushMicrotasks();
      state.setLaunchAtStartup(true);
      async.flushMicrotasks();
      expect(state.launchAtStartup, isFalse);
      state.dispose();
    });
  });
}
