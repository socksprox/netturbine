# netturbine

Fan control for the **HP OmniBook 7 (17-dc0xxx)** from the Windows system
tray. A compact Windows 11-style flyout (built with Flutter desktop) on top
of a small elevated helper service that talks to the laptop's embedded
controller.

## Features

- Lives in the notification-area overflow (the "^" chevron) — click to reveal,
  no taskbar entry
- Per-fan manual speed slider (0–100 %) with an explicit "return to auto"
- Temporary boost: max speed for 15 minutes, then hands control back to the
  firmware
- Temperature readings (CPU package, EC thermal zones, NVMe)
- "Launch at startup" toggle (per-user, no admin needed)
- Light/dark theme matching Windows 11

## Hardware support

Fan control is validated on the **HP OmniBook 7 17-dc0xxx** (Insyde BIOS) —
the EC register map in `windows/tools/fan_helper.cpp` is read from that
machine's DSDT. On other machines the app still runs fine; it simply reports
no controllable fans instead of guessing at registers.

There is no RPM telemetry — fan speed is reported as percent only.

## Requirements

- Windows 10/11 x64
- [PawnIO](https://pawnio.eu/) driver installed (provides `PawnIOLib.dll`;
  same mechanism LibreHardwareMonitor/FanControl use)
- One-time administrator elevation to install the `NetturbineFanHelper`
  service — the app itself and all base features (tray, startup toggle,
  settings) run unelevated

## Install

Grab `Netturbine-<version>-x64.exe` from `dist/` (or build it yourself, see
below). The installer offers a finish-page checkbox, "Install fan control
service", which triggers a single UAC prompt and registers the helper
service. Skip it and the app still works minus fan control. The uninstaller
removes the service automatically.

## How it works

```
lib/ui ──> lib/app ──> lib/api        (pure Dart, strict layering)
                          │
                MethodChannel "netturbine/fan"
                          │
              windows/runner (Win32)
                          │
              \\.\pipe\netturbine_fan
                          │
   NetturbineFanHelper service (elevated)
                          │
            PawnIO → EC ports 0x62/0x66
```

The app never touches hardware directly. The unelevated runner proxies a
tiny line-based pipe protocol (`list`, `read <i>`, `set <i> <pct>`,
`auto <i>`, `temps`, …) to the elevated helper service, which owns the
PawnIO driver handle and serializes EC access through the global
`Access_EC` mutex so it does not race `acpi.sys`.

Dependency direction is strict — `ui` → `app` → `api` — and only
`lib/api/windows/` may use `MethodChannel`/`dart:io`. The API layer is
platform-agnostic so a macOS implementation can be added later without
touching app or UI code. Scoped conventions live in the `AGENTS.md` files
in each directory.

## Development

Requires the Flutter SDK (Dart 3.13+) on Windows.

```sh
flutter pub get
flutter analyze      # must stay clean
flutter test
flutter run -d windows
```

Run against fake fans (no helper service needed):

```sh
flutter run -d windows --dart-define=NETTURBINE_SIMULATE=true
```

Launch flags on the built exe: `--show` opens the window instead of
starting hidden to tray. A second launch signals the running instance via
a named mutex rather than opening a duplicate.

## Building the installer

```sh
dart run run_build.dart
```

Requires `windows/tools/fan_helper.exe` plus `LpcACPIEC.bin` and
`IntelMSR.bin` alongside it (built from `fan_helper.cpp` with any MSVC
toolchain). The script bundles the helper into the Release output,
generates and patches an Inno Setup script (via `inno_bundle`), compiles
it with ISCC — installed or auto-fetched — and drops
`Netturbine-<version>-x64.exe` into `dist/`.

## Debugging tools

`windows/tools/` contains standalone probes used to reverse-engineer and
verify the EC interface: `ec_probe.exe` (arbitrary EC read/write),
`acpi_probe.exe`, `msr_probe.exe`, `fan_helper.exe console` (run the pipe
server in the foreground), and assorted PowerShell/Dart scripts for ACPI
dumps and register scans.
