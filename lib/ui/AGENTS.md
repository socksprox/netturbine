# UI layer (lib/ui/)

Goal: looks like a native Windows 11 app, built with Flutter core only.

## Rules

- **No third-party UI packages** — no `fluent_ui`, `fluentui_system_icons`, icon fonts, etc. Build the look with `material`/`widgets`/`painting` and custom painters where needed
- **No shared design package** — the theme lives in `ui/theme.dart` in this repo
- Typography: Segoe UI Variable (`fontFamily: 'Segoe UI Variable Text'`, fallback `'Segoe UI'`); Windows 11 scale — caption 12, body 14, subtitle 20, title 28
- Colors: Win11 surfaces (`#f9f9f9` light / `#202020` dark, cards `#fdfdfd` / `#2c2c2c`), 1px borders (`#e5e5e5` / `#404040`), accent `#0067c0` light / `#4cc2ff` dark; read the system accent via `api/` if exposed
- Shape: 8px radius on cards/window chrome, 4px on controls, 8px spacing grid
- Controls mimic Windows 11: thin slider track with round thumb, pill toggle switches, subtle hover/pressed states, flyout-style menus
- Light and dark `ThemeData`; honor `MediaQuery.platformBrightnessOf(context)`
- The app lives behind a tray icon — window is compact (~360×420), fixed size, popover-style layout

Keep widgets dumb: read state from `lib/app`, call methods on the abstract `FanController`. No business logic, no `dart:io` here.
