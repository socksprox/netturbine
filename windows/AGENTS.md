# Windows runner (windows/)

Native OS integration lives here. Keep the Flutter runner template as close to stock as possible so `flutter upgrade` diffs stay small.

## Responsibilities

- **Tray icon** — `Shell_NotifyIcon` in the runner (notification area — the "^" overflow chevron). Both left- and right-click toggle the Flutter window; quitting happens via the in-app Quit button (`quitApp` channel). No third-party tray packages.
- **Start on startup** — `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` entry. HKCU only: toggling must never require admin.
- **Single instance** — named mutex; a second launch signals the first to show its window.
- **Window** — no taskbar entry (`WS_EX_TOOLWINDOW`), app starts hidden to tray unless launched with `--show`.
- **Fan backends** — `windows/tools/fan_helper.cpp` is organized around pluggable `FanBackend`s probed at startup; every detected fan maps into one index space. Current backends:
  - **Nuvoton Super I/O** (`SuperIoFans`) — the standard desktop fan controller (NCT6779D / NCT679x family; validated on an MSI B450M PRO-VDH MAX with NCT6795D). Mechanism: PawnIO `LpcIO.bin` (config port 0x2E/0x4E + hwmon I/O port, BAR-whitelisted by `ioctl_find_bars`), serialized via the global `Access_ISABUS.HTP.Method` mutex — same as LibreHardwareMonitor/FanControl. Detection, register map, and RPM math mirror LHM's `Nct677X`. Channels whose tach counter reads "no fan" are hidden so unpopulated headers don't show up.
  - **ACPI EC** (`EcFans`) — validated on the HP OmniBook 7 17-dc0xxx (Insyde BIOS). Mechanism: PawnIO `LpcACPIEC.bin` (ports 0x62/0x66) via `Access_EC`. Gated on `SystemProductName` containing "OmniBook" so unknown ECs are never probed.
  - **AMD GPU** (`AdlxFans`) — validated on an RX 6800 (RDNA2). Mechanism: ADLX (`amdadlx64.dll`, driver-provided) loaded via `LoadLibraryExW` + `GetProcAddress`; no driver file is bundled — SDK headers under `windows/tools/adlx/` are compile-time only. One channel per GPU that passes `IsSupportedManualFanTuning`; hold via `SetTargetFanSpeed` (RPM) when supported, else flattened fan-tuning states; `auto` re-applies factory/baseline states. Telemetry (`GPUFanSpeed` RPM, `GPUFanDuty` %, edge/hotspot temps) via `IADLXPerformanceMonitoringServices`. Init is SEH-guarded (`AdlxInitGuarded`) so a broken ADLX install can't crash the service.
- Exposed to Dart through the `netturbine/fan` MethodChannel in `runner/flutter_window.cpp`, which proxies to the helper over `\\.\pipe\netturbine_fan` — never directly by `lib/ui` or `lib/app`.

## Fan backend (confirmed working)

- `windows/tools/fan_helper.cpp` builds `fan_helper.exe` — a Windows service (`NetturbineFanHelper`) hosting the pipe. Commands: `ping`, `backend`, `caps` (bit0 = RPM), `list`, `name <i>`, `read <i>` (percent), `rpm <i>`, `mode <i>` (0=auto/1=manual), `set <i> <pct>`, `auto <i>`, `temp` (CPU package °C), `temps` (all sensors as `label=celsius` pairs; `_` = space). `caps`/`name`/`rpm`/`backend` are newer — old helpers answer `err`, the runner falls back. Run `fan_helper.exe install` **elevated once** to register it; `console` runs it in the foreground for debugging (needs elevation — `pawnio_open` rejects unprivileged access). The PawnIO module blobs (`LpcACPIEC.bin`, `LpcIO.bin`, `IntelMSR.bin`) must sit next to the exe or in `pawnio_modules\`.
- Rebuild: `build_helper.bat` (or `cl /EHsc /W3 /O2 fan_helper.cpp advapi32.lib` in a VS dev prompt); then swap the running service with `swap_helper.ps1` **elevated** (expects the new binary as `fan_helper_new.exe`).
- **Watchdog**: the service clears manual holds when no pipe command arrives for ~30s. The app polls `getFans` every 2s while running, so this only fires after app exit/crash — firmware regains control rather than leaving fans pinned at a stale setpoint.
- EC register map (OmniBook DSDT, verified live): fan 0 — read `0x95`, write `0x94`, hold `0x93` bit `0x10`; fan 1 — read `0x83`, write `0x82`, hold `0x81` bit `0x10`. Values are percent 0–100. Setting the hold bit makes the setpoint stick; clearing it returns the fan to firmware control.
- Nuvoton register map (NCT679x, banked at hwmon base+5/+6): PWM out `{0x001,0x003,0x011,0x013,0x015,0x017|0xA09,0x029|0xB09}`, PWM command `{bank:09}` at `0x109..0xB09`, mode `{bank:02}` at `0x102..0xB02` (0 = software control), 13-bit tach `{0x4B0..0x4BA,0x4CC}` with RPM = 1.35e6/count (count < 0x15 = absent, ≥ 0x1FFF = stopped). Manual set saves mode+command once and restores them on `auto`.
- `ec_probe.exe` / `acpi_probe.exe` / `msr_probe.exe` in the same dir are standalone probes for debugging; `pipe_probe.ps1` sends one pipe command.
- User-mode `IOCTL_ACPI_EVAL_METHOD` does **not** work on the OmniBook (interface rejects with ERROR_NOT_SUPPORTED) — don't retry that path; PawnIO is the mechanism.
- RPM telemetry exists on the Super I/O path (`canReadRpm` via `caps` bit0); the OmniBook EC reports percent only.
- **Temperatures**: CPU package/die via a `CpuPackageTemp` façade that picks by `VendorIdentifier` — Intel via PawnIO `IntelMSR.bin` (`IA32_PACKAGE_THERM_STATUS` / `IA32_TEMPERATURE_TARGET`, gated on `GenuineIntel` so the MSRs never execute on AMD), AMD via `AMDFamily17.bin` (`ioctl_read_smn` on SMN `0x59800`, Tctl in bits 31:21 at 1/8 °C; gated on `AuthenticAMD`); EC thermal-sensor block `THS0`–`THSF` at offsets `0xA8`–`0xB7` (OmniBook); Nuvoton temp inputs (CPUTIN→"CPU socket", SYSTIN→"Motherboard", AUXTINn→"Aux N", PECI→"CPU PECI") filtered to sane ranges, identical readings deduplicated (boards mirror one physical source into several monitor slots); SSD/NVMe composite temp via `StorageDeviceTemperatureProperty` (`IOCTL_STORAGE_QUERY_PROPERTY` on `\\.\PhysicalDriveN`).

## Rules

- Comment every FFI/channel call site: method name, expected args, error contract
- If the fan backend needs elevation, isolate it and say so clearly — base features (tray, startup toggle, settings) must work unelevated
