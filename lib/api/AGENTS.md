# Platform API layer (lib/api/)

This directory is the portability boundary. Every contract here must be implementable on Windows today and macOS later.

## Rules

- Pure Dart only in the abstractions: no `package:flutter`, `dart:ffi`, `dart:io`, or `MethodChannel`
- Contracts are abstract classes + immutable data types:
  - `FanController` — `fans`, `getSpeed`, `setSpeed(percent)`, `resetToAuto`, `capabilities`
  - `FanInfo` — id, label, rpm, percent, `canControl`
  - Capability flags (`canReadRpm`, `canSetSpeed`) — never assume a fan is controllable
- All operations async (`Future`, `Stream<FanInfo>` for polling); failures throw a typed `FanControlException`, never crash
- No OS concepts in shared types: no registry keys, WMI class names, device paths, or Windows error codes. Keep names generic — `speedPercent`, not `pwmDuty`
- Concrete OS code lives in `lib/api/<os>/` subdirectories. Each impl exposes a factory; `fan_controller.dart` holds `FanController.forCurrentPlatform()` with an `UnsupportedFanController` fallback
- Temporary boost ("max for 15 min") belongs in `lib/app/` as a timer over `setSpeed` + `resetToAuto` — the API stays dumb

## Adding a platform

Create `lib/api/<os>/`, implement `FanController`, register it in the factory. If done right, `lib/ui` and `lib/app` need zero changes.
