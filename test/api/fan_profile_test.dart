import 'package:flutter_test/flutter_test.dart';
import 'package:netturbine/api/fan_profile.dart';

void main() {
  FanProfile profile() => FanProfile(
        id: 'test',
        name: 'Test',
        sensorId: 'cpu',
        points: const [
          CurvePoint(temp: 40, percent: 20),
          CurvePoint(temp: 60, percent: 50),
          CurvePoint(temp: 80, percent: 100),
        ],
      );

  test('interpolates linearly between points', () {
    expect(profile().speedFor(50), 35);
    expect(profile().speedFor(70), 75);
  });

  test('clamps to the end points outside the curve range', () {
    expect(profile().speedFor(20), 20);
    expect(profile().speedFor(100), 100);
  });

  test('returns null when the sensor reading is unavailable', () {
    expect(profile().speedFor(null), isNull);
  });

  test('sorts unsorted points on construction', () {
    final p = FanProfile(
      id: 'x',
      name: 'x',
      sensorId: 'cpu',
      points: const [
        CurvePoint(temp: 80, percent: 100),
        CurvePoint(temp: 40, percent: 20),
      ],
    );
    expect(p.speedFor(30), 20);
    expect(p.speedFor(60), 60);
  });

  test('a single point behaves like a fixed speed', () {
    final p = FanProfile(
      id: 'x',
      name: 'x',
      sensorId: 'cpu',
      points: const [CurvePoint(temp: 50, percent: 42)],
    );
    expect(p.speedFor(10), 42);
    expect(p.speedFor(99), 42);
  });

  test('duplicate temps do not divide by zero', () {
    final p = FanProfile(
      id: 'x',
      name: 'x',
      sensorId: 'cpu',
      points: const [
        CurvePoint(temp: 50, percent: 10),
        CurvePoint(temp: 50, percent: 60),
      ],
    );
    // A shared temperature acts like a step: the earlier point holds at
    // exactly 50°C, the later one takes over just above it.
    expect(p.speedFor(50), 10);
    expect(p.speedFor(51), 60);
  });

  test('JSON round-trips name, sensor, points and custom flag', () {
    final original = FanProfile(
      id: 'custom-1',
      name: 'My curve',
      sensorId: 'skin',
      points: const [
        CurvePoint(temp: 40, percent: 10),
        CurvePoint(temp: 90, percent: 90),
      ],
    );
    final restored =
        FanProfile.fromJson(original.toJson());
    expect(restored, isNotNull);
    expect(restored, original);
    expect(restored!.builtIn, isFalse);
  });

  test('built-in profiles exist and report isModified on edits', () {
    final quiet = FanProfile.factoryVersion('quiet')!;
    expect(quiet.isModified, isFalse);
    final edited = quiet.copyWith(points: const [
      CurvePoint(temp: 50, percent: 50),
      CurvePoint(temp: 90, percent: 100),
    ]);
    expect(edited.isModified, isTrue);
    expect(FanProfile.builtInProfiles, hasLength(3));
  });
}
