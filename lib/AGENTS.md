# lib/ conventions

## Dart style

- `flutter analyze` clean; no dead code, no ignored lints without a comment explaining why
- `const` constructors wherever possible
- Public types in `api/` get `///` doc comments; internal widgets don't need them
- One widget/class per file unless they're tightly coupled

## Layering

- `lib/api/` — pure Dart, **no `package:flutter` imports**. Abstract contracts + data types. See `api/AGENTS.md`
- `lib/api/windows/` — the only Dart code allowed to import `dart:ffi`, `dart:io`, or platform channels
- `lib/app/` — app state (`ChangeNotifier`/streams — no state-management packages), settings persistence, boost timers
- `lib/ui/` — widgets + theme; depends only on `lib/app` and the abstract types in `lib/api`, never the concrete Windows impl
- `main.dart` — wires the platform impl into `app` and launches `ui`

Backend selection happens once, in `main.dart`:

```dart
final fan = FanController.forCurrentPlatform(); // Windows impl; stub elsewhere
```

Never `import 'dart:io'` in `lib/ui` or `lib/app` to check the platform — ask `api/` for capabilities instead.
