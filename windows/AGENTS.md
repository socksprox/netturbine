# Windows runner (windows/)

Native OS integration lives here. Keep the Flutter runner template as close to stock as possible so `flutter upgrade` diffs stay small.

## Responsibilities

- **Tray icon** — `Shell_NotifyIcon` in the runner (notification area — the "^" overflow chevron). Both left- and right-click toggle the Flutter window; quitting happens via the in-app Quit button (`quitApp` channel). No third-party tray packages.
- **Start on startup** — `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry. HKCU only: toggling must never require admin.
- **Single instance** — named mutex; a second launch signals the first to show its window.
- **Window** — no taskbar entry (`WS_EX_TOOLWINDOW`), app starts hidden to tray unless launched with `--show`.
- **Fan backend** — validated on the target machine (HP OmniBook 7 17-dc0xxx, Insyde BIOS): the fans live in the embedded controller. Mechanism: **PawnIO** signed driver + `LpcACPIEC.bin` module (EC I/O ports 0x62/0x66), serialized via the global `Access_EC` mutex. Exposed to Dart through the `netturbine/fan` MethodChannel in `runner/flutter_window.cpp`, which proxies to the helper over `\\.\pipe\netturbine_fan` — never directly by `lib/ui` or `lib/app`.

## Fan backend (confirmed working)

- `windows/tools/fan_helper.cpp` builds `fan_helper.exe` — a Windows service (`NetturbineFanHelper`) hosting the pipe. Commands: `ping`, `list`, `read <i>` (percent), `mode <i>` (0=auto/1=manual), `set <i> <pct>`, `auto <i>`, `temp` (CPU package °C), `temps` (all sensors as `label=celsius` pairs; `_` = space). Run `fan_helper.exe install` **elevated once** to register it; `console` runs it in the foreground for debugging. `LpcACPIEC.bin` and `IntelMSR.bin` must sit next to the exe.
- Rebuild (VS dev prompt / vcvars64): `cl /EHsc /W3 /O2 fan_helper.cpp advapi32.lib` → produces `fan_helper.exe`; then swap the running service with `swap_helper.ps1` **elevated** (expects the new binary as `fan_helper_new.exe`).
- **Watchdog**: the service clears the manual-hold bits when no pipe command arrives for ~30s. The app polls `getFans` every 2s while running, so this only fires after app exit/crash — firmware regains control rather than leaving fans pinned at a stale setpoint.
- EC register map (from the machine's DSDT, verified live): fan 0 — read `0x95`, write `0x94`, hold `0x93` bit `0x10`; fan 1 — read `0x83`, write `0x82`, hold `0x81` bit `0x10`. Values are percent 0–100. Setting the hold bit makes the setpoint stick; clearing it returns the fan to firmware control.
- `ec_probe.exe` in the same dir is a standalone read/write probe for debugging.
- User-mode `IOCTL_ACPI_EVAL_METHOD` does **not** work on this machine (interface rejects with ERROR_NOT_SUPPORTED) — don't retry that path; PawnIO is the mechanism.
- No RPM telemetry — `speedPercent` only; `canReadRpm` is false.
- **Temperatures**: CPU package via PawnIO `IntelMSR.bin` (`IA32_PACKAGE_THERM_STATUS` / `IA32_TEMPERATURE_TARGET`); EC thermal-sensor block `THS0`–`THSF` at EC offsets `0xA8`–`0xB7` — entries of `0x00` or `≥0x80` are unpopulated and filtered out. Names come from the DSDT: `ECMB` is a SystemMemory mailbox at `0xFE802000`, where a second `Field(ECMB)` block aliases `THS0`–`THS4` as `CPUT`/`MSKT`/`AMBT`/`VDIN`/`PCHT` (CPU, skin, ambient, DC-in/VRM area, PCH); unaliased slots report as "Zone N". `THS0`/`THS1` back ACPI thermal zones `TZS0`/`TZS1` (`TZS0._PSL` lists processors). SSD/NVMe composite temp via `StorageDeviceTemperatureProperty` (`IOCTL_STORAGE_QUERY_PROPERTY` on `\\.\PhysicalDriveN`).

## Rules

- Comment every FFI/channel call site: method name, expected args, error contract
- If the fan backend needs elevation, isolate it and say so clearly — base features (tray, startup toggle, settings) must work unelevated
