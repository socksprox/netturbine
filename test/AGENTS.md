# Tests (test/)

- Mirror `lib/` structure: `lib/api/foo.dart` → `test/api/foo_test.dart`
- `flutter test` must pass before a change is considered done
- Test `lib/api` contracts against a `FakeFanController` (in-memory). Never touch real hardware, registry, or WMI in tests
- `lib/app` logic (boost timer, settings round-trip) is unit-tested with fakes; timer tests use `fake_async`
- Widget tests pump the shell with `FakeFanController` — assert slider/menu state and behavior, not pixel-perfect styling
- No golden-file tests; the Windows 11 look is verified manually
