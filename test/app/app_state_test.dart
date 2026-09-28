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
      expect(state.manualTarget('cpu'), isNull);
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

  test('setSpeed records the manual target; resetToAuto clears it', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.setSpeed('cpu', 25);
      async.flushMicrotasks();
      expect(state.manualTarget('cpu'), 25);

      state.resetToAuto('cpu');
      async.flushMicrotasks();
      expect(state.manualTarget('cpu'), isNull);
      state.dispose();
    });
  });

  test('a failed setSpeed does not record a manual target', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu])..throwOnControl = true;
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();

      state.setSpeed('cpu', 25);
      async.flushMicrotasks();
      expect(state.manualTarget('cpu'), isNull);
      expect(state.backendError, isTrue);
      state.dispose();
    });
  });

  test('selectFixed holds the current speed as the target', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]); // speedPercent: 40
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.selectFixed();
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 40);
      expect(state.fanMode, FanMode.fixed);
      state.dispose();
    });
  });

  test('selectAuto releases manual holds', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.selectFixed();
      state.setSpeed('cpu', 70);
      async.flushMicrotasks();
      state.selectAuto();
      async.flushMicrotasks();
      expect(fan.resetCalls, contains('cpu'));
      expect(state.manualTarget('cpu'), isNull);
      state.dispose();
    });
  });

  test('profile mode writes the curve output on each snapshot', () {
    fakeAsync((async) {
      final fan = FakeFanController(
        fans: [_cpu],
        sensors: const [
          TempSensor(id: 'cpu', label: 'CPU', celsius: 70),
        ],
      );
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      // Balanced at 70°C = 50%.
      state.selectProfile('balanced');
      async.flushMicrotasks();
      expect(state.fanMode, FanMode.profile);
      expect(fan.speeds['cpu'], 50);
      expect(state.manualTarget('cpu'), 50);

      // Temperature rises above the hysteresis band → rewritten.
      fan.sensors = const [
        TempSensor(id: 'cpu', label: 'CPU', celsius: 90)
      ];
      fan.emit();
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 88);
      state.dispose();
    });
  });

  test('curve falls back to firmware when the sensor goes missing', () {
    fakeAsync((async) {
      final fan = FakeFanController(
        fans: [_cpu],
        sensors: const [
          TempSensor(id: 'cpu', label: 'CPU', celsius: 70),
        ],
      );
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();
      state.selectProfile('balanced');
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 50);

      fan.sensors = const [];
      fan.emit();
      async.flushMicrotasks();
      expect(fan.resetCalls, contains('cpu'));
      state.dispose();
    });
  });

  test('boost restores the previous mode instead of going auto', () {
    fakeAsync((async) {
      final fan = FakeFanController(fans: [_cpu]);
      final state =
          AppState(fan: fan, system: FakeSystemIntegration());
      state.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();

      state.selectFixed();
      state.setSpeed('cpu', 30);
      async.flushMicrotasks();

      state.startBoost();
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 100);

      state.cancelBoost();
      async.flushMicrotasks();
      expect(fan.speeds['cpu'], 30);
      state.dispose();
    });
  });

  test('mode, profile edits and fixed targets persist across restarts', () {
    fakeAsync((async) {
      final system = FakeSystemIntegration();
      final fan = FakeFanController(fans: [_cpu]);

      final first = AppState(fan: fan, system: system);
      first.init();
      async.flushMicrotasks();
      fan.emit();
      async.flushMicrotasks();
      first.selectProfile('quiet');
      async.flushMicrotasks();
      first.updateProfile(
        first.activeProfile!.copyWith(name: 'Very quiet'),
      );
      async.flushMicrotasks();
      first.dispose();
      async.flushMicrotasks();

      expect(system.settingsJson, isNotNull);

      final second = AppState(fan: fan, system: system);
      second.init();
      async.flushMicrotasks();
      expect(second.fanMode, FanMode.profile);
      expect(second.activeProfileId, 'quiet');
      expect(second.activeProfile!.name, 'Very quiet');
      second.dispose();
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
