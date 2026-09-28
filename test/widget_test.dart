import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:netturbine/api/fan_controller.dart';
import 'package:netturbine/app/app_state.dart';
import 'package:netturbine/ui/app.dart';
import 'package:netturbine/ui/widgets/win_toggle.dart';

import 'fakes.dart';

void main() {
  testWidgets('shows fans, slider, boost button and startup toggle',
      (tester) async {
    final fan = FakeFanController(
      fans: const [
        FanInfo(
            id: 'cpu',
            label: 'CPU Fan',
            rpm: 1200,
            speedPercent: 40,
            canControl: true),
      ],
    );
    final state = AppState(fan: fan, system: FakeSystemIntegration());
    await state.init();
    fan.emit();

    await tester.pumpWidget(NetturbineApp(state: state));
    await tester.pump();

    expect(find.text('netturbine'), findsOneWidget);
    expect(find.text('Fan control'), findsOneWidget);
    expect(find.text('Automatic'), findsOneWidget);
    expect(find.text('CPU Fan'), findsOneWidget);
    expect(find.text('1200 RPM'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    expect(find.text('Max speed for 15 min'), findsOneWidget);
    expect(find.text('Start on startup'), findsOneWidget);
    expect(find.byType(WinToggle), findsOneWidget);
  });

  testWidgets('profile mode shows the curve editor', (tester) async {
    final fan = FakeFanController(
      fans: const [
        FanInfo(
            id: 'cpu',
            label: 'CPU Fan',
            rpm: 1200,
            speedPercent: 40,
            canControl: true),
      ],
      sensors: const [
        TempSensor(id: 'cpu', label: 'CPU', celsius: 55),
      ],
    );
    final state = AppState(fan: fan, system: FakeSystemIntegration());
    await state.init();
    fan.emit();

    await tester.pumpWidget(NetturbineApp(state: state));
    await tester.pump();

    await state.selectProfile('balanced');
    await tester.pump();

    expect(find.text('Sensor'), findsOneWidget);
    expect(find.text('Point'), findsOneWidget);
    expect(find.textContaining('°C'), findsWidgets);
    // Slider is read-only in profile mode.
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.onChanged, isNull);
    state.dispose();
  });

  testWidgets('shows empty state when no fans are controllable',
      (tester) async {
    final state = AppState(
      fan: FakeFanController(),
      system: FakeSystemIntegration(),
    );
    await state.init();

    await tester.pumpWidget(NetturbineApp(state: state));
    await tester.pump();

    expect(find.textContaining('No controllable fans'), findsOneWidget);
    expect(find.byType(Slider), findsNothing);
  });
}
