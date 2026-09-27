# Windows runner (windows/)

Native OS integration lives here. Keep the Flutter runner template as close to stock as possible so `flutter upgrade` diffs stay small.

## Responsibilities

- **Tray icon** — `Shell_NotifyIcon` in the runner (notification area — the "^" overflow chevron). Left-click toggles the Flutter window; right-click shows a context menu (Open / Quit). No third-party tray packages.
- **Start on startup** — `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry. HKCU only: toggling must never require admin.
- **Single instance** — named mutex; a second launch signals the first to show its window.
- **Window** — no taskbar entry (`WS_EX_TOOLWINDOW`), app starts hidden to tray unless launched with `--show`.
- **Fan backend** — hardware access is driver/EC/vendor-specific; document the chosen mechanism in `runner/` when decided. Expose it to Dart via FFI or a `MethodChannel` consumed by `lib/api/windows/` — never directly by `lib/ui` or `lib/app`.

## Rules

- Comment every FFI/channel call site: method name, expected args, error contract
- If the fan backend needs elevation, isolate it and say so clearly — base features (tray, startup toggle, settings) must work unelevated
