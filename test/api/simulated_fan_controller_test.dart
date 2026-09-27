import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netturbine/api/fan_controller.dart';
import 'package:netturbine/api/simulated/simulated_fan_controller.dart';

void main() {
  test('exposes two controllable fans with capabilities', () {
    fakeAsync((async) {
      final controller = SimulatedFanController();
      expect(controller.fans, hasLength(2));
      expect(controller.fans.every((f) => f.canControl), isTrue);
      expect(controller.capabilities.canSetSpeed, isTrue);
      expect(controller.capabilities.canReadRpm, isTrue);
      async.elapse(const Duration(seconds: 2));
      controller.dispose();
    });
  });

  test('setSpeed overrides and resetToAuto restores auto mode', () async {
    final controller = SimulatedFanController();
    await controller.setSpeed('cpu', 80);
    expect(controller.fans.firstWhere((f) => f.id == 'cpu').speedPercent, 80);
    expect(controller.fans.firstWhere((f) => f.id == 'cpu').isAuto, isFalse);

    await controller.resetToAuto('cpu');
    expect(controller.fans.firstWhere((f) => f.id == 'cpu').isAuto, isTrue);
    await controller.dispose();
  });

  test('unknown fan id throws FanControlException', () async {
    final controller = SimulatedFanController();
    expect(() => controller.setSpeed('nope', 50),
        throwsA(isA<FanControlException>()));
    await controller.dispose();
  });
}
