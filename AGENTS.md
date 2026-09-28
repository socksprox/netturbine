# netturbine

Windows fan-control app. Flutter desktop UI on top of a platform-agnostic fan-control API layer. Windows ships first; the API is designed so macOS support can be added later without touching app or UI code.

## Stack

- Flutter desktop (`flutter run -d windows`), Dart 3
- C++ only inside `windows/` for OS integration
- Minimal pub.dev dependencies — justify every addition in the PR
- UI is built from Flutter core widgets only — no `fluent_ui` or other UI kits, and no internal "design package"; the theme lives in `lib/ui/theme.dart`

## Architecture

```
lib/
  api/          platform-agnostic boundary — pure Dart abstractions
    windows/    Windows implementation of the api/ contracts
  app/          wiring: app state, settings, boost timers, startup/tray glue
  ui/           Windows 11-style widgets and theme
windows/        Flutter runner + native code (tray icon, fan backend)
test/           mirrors lib/
```

Dependency direction is strict: `ui` → `app` → `api`. Nothing outside `lib/api/` may touch `dart:ffi`, `MethodChannel`, `dart:io` platform checks, or Windows-specific APIs. Scoped rules live in `lib/api/AGENTS.md`, `lib/ui/AGENTS.md`, `windows/AGENTS.md`, `test/AGENTS.md` — read them before editing those directories.

If the Flutter scaffold doesn't exist yet, create it with `flutter create --platforms=windows .` (add `macos` only when the macOS impl is actually being built).

## Feature scope

Keep it small:

- System-tray presence (notification-area overflow — the "^" chevron); click reveals the app
- "Start on startup" setting
- Manual fan-speed slider override
- Temporary boost button (e.g. "max speed for 15 min")

No dashboards, no sensor graphs beyond what's needed to label fans.

## Commands

- `flutter pub get`
- `flutter analyze` — must be clean before committing
- `flutter test`
- `flutter run -d windows`
- `flutter build windows`
- `dart run run_build.dart` — release installer via Inno Setup → `dist/` (Windows only)

## General rules

- Match the Windows 11 visual language; when unsure, imitate Windows Settings
- Fan control can fail or be unsupported on a machine — every API call must degrade gracefully and surface state to the UI, never crash
- Never log or expose hardware identifiers, EC register dumps, or driver paths
