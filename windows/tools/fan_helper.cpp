// fan_helper — elevated helper for netturbine fan control.
//
// Hardware is reached through pluggable backends, probed at startup:
//   - Nuvoton Super I/O (NCT6779D / NCT679x family) via the PawnIO LpcIO
//     module — the standard fan controller on desktop motherboards.
//     Detection and register map mirror LibreHardwareMonitor's Nct677X.
//   - ACPI embedded controller via the PawnIO LpcACPIEC module — validated
//     on the HP OmniBook 7 (17-dc0xxx, Insyde BIOS). Only enabled when the
//     system product name reports an OmniBook; never probed elsewhere.
// Fans from all active backends share one index space.
//
// Serves named pipe \\.\pipe\netturbine_fan with a line-based protocol:
//   ping                -> "pong"
//   backend             -> "ok <name[+name...]>"   (active backends, "none")
//   caps                -> "ok <flags>"            (bit0: rpm telemetry)
//   list                -> "ok <n>"                (fan count)
//   name <fan>          -> "ok <label>"            ('_' = space)
//   read <fan>          -> "ok <percent>"          (0-100)
//   rpm <fan>           -> "ok <rpm>"              (when caps bit0)
//   mode <fan>          -> "ok <0|1>"              (0 auto, 1 manual hold)
//   set <fan> <pct>     -> "ok"                    (holds fan at pct)
//   auto <fan>          -> "ok"                    (firmware control)
//   temp                -> "ok <celsius>"          (CPU package temp)
//   temps               -> "ok L=c [L=c ...]"      (all temp sensors; '_' = space)
//   anything else       -> "err <msg>"
//
// Modes:
//   fan_helper.exe install    — register + start the Windows service
//   fan_helper.exe uninstall  — stop + remove the service
//   fan_helper.exe console    — run the pipe server in the foreground
//   (no args, SCM-launched)   — service entry point
//
// Safety: a watchdog releases manual holds when no pipe command arrives
// for ~30s, so a crashed/exited app never leaves fans pinned at a stale
// setpoint.

#include <windows.h>
#include <winioctl.h>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

typedef HRESULT(STDAPICALLTYPE* pawnio_open_fn)(PHANDLE);
typedef HRESULT(STDAPICALLTYPE* pawnio_load_fn)(HANDLE, const UCHAR*, SIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_execute_fn)(HANDLE, PCSTR,
                                                 const ULONG64*, SIZE_T,
                                                 PULONG64, SIZE_T, PSIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_close_fn)(HANDLE);

struct MutexLock {
  explicit MutexLock(HANDLE m) : m_(m) {
    if (m_) WaitForSingleObject(m_, 3000);
  }
  ~MutexLock() { if (m_) ReleaseMutex(m_); }
  HANDLE m_;
};

// Resolves a PawnIO module blob: next to the exe first (installed layout),
// then <exe>\pawnio_modules\ (repo layout for console debugging).
static bool ReadModuleBlob(const wchar_t* name, std::vector<BYTE>* blob) {
  wchar_t dir[MAX_PATH];
  GetModuleFileNameW(nullptr, dir, MAX_PATH);
  wchar_t* slash = wcsrchr(dir, L'\\');
  if (slash) *slash = 0;
  HANDLE f = INVALID_HANDLE_VALUE;
  for (int i = 0; i < 2 && f == INVALID_HANDLE_VALUE; i++) {
    std::wstring path = std::wstring(dir) + (i == 0 ? L"\\" : L"\\pawnio_modules\\") + name;
    f = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                    OPEN_EXISTING, 0, nullptr);
  }
  if (f == INVALID_HANDLE_VALUE) return false;
  DWORD sz = GetFileSize(f, nullptr);
  blob->resize(sz);
  DWORD rd = 0;
  ReadFile(f, blob->data(), sz, &rd, nullptr);
  CloseHandle(f);
  return rd == sz;
}

// Shared PawnIO binding: one driver handle + one loaded module blob.
class PawnIo {
 public:
  ~PawnIo() {
    if (pio_ && close_) close_(pio_);
    if (lib_) FreeLibrary(lib_);
  }

  bool Load(const wchar_t* blobName) {
    lib_ = LoadLibraryW(L"PawnIOLib.dll");  // resolves via PATH / installed dir
    if (!lib_) lib_ = LoadLibraryW(L"C:\\Program Files\\PawnIO\\PawnIOLib.dll");
    if (!lib_) return Fail("PawnIOLib.dll not found");
    exec_ = (pawnio_execute_fn)GetProcAddress(lib_, "pawnio_execute");
    auto open = (pawnio_open_fn)GetProcAddress(lib_, "pawnio_open");
    auto load = (pawnio_load_fn)GetProcAddress(lib_, "pawnio_load");
    close_ = (pawnio_close_fn)GetProcAddress(lib_, "pawnio_close");
    if (!exec_ || !open || !load || !close_) return Fail("PawnIOLib exports");
    if (FAILED(open(&pio_)) || !pio_) return Fail("pawnio_open");

    std::vector<BYTE> blob;
    if (!ReadModuleBlob(blobName, &blob)) return Fail("module blob not found");
    if (FAILED(load(pio_, blob.data(), blob.size()))) return Fail("pawnio_load");
    return true;
  }

  int Exec(const char* ioctl, const ULONG64* in, SIZE_T inCount, ULONG64* out,
           SIZE_T outCount) {
    if (!exec_ || !pio_) return -1;  // module never loaded
    SIZE_T ret = 0;
    return FAILED(exec_(pio_, ioctl, in, inCount, out, outCount, &ret)) ? -1 : 0;
  }

  const char* Error() const { return err_; }

 private:
  bool Fail(const char* e) {
    strncpy_s(err_, e, _TRUNCATE);
    return false;
  }

  HMODULE lib_ = nullptr;
  HANDLE pio_ = nullptr;
  pawnio_execute_fn exec_ = nullptr;
  pawnio_close_fn close_ = nullptr;
  char err_[128] = {};
};

// --------------------------------------------------------- backend contract

// One detected fan source (EC, Super I/O chip, ...). Indices are the
// backend's own channel numbers; the pipe layer maps them onto the merged
// global index space.
class FanBackend {
 public:
  virtual ~FanBackend() = default;
  virtual const char* Name() const = 0;
  virtual const char* Error() const = 0;
  virtual int FanCount() const = 0;
  virtual const char* FanLabel(int channel) const = 0;  // '_' for spaces
  virtual bool HasRpm() const = 0;
  virtual int ReadPercent(int channel, int* percent) = 0;
  virtual int ReadRpm(int channel, int* rpm) = 0;  // -1 unsupported
  virtual int SetPercent(int channel, int percent) = 0;
  virtual int SetAuto(int channel) = 0;
  virtual int IsManual(int channel) = 0;  // 1 manual, 0 auto, -1 error
  virtual void AppendTemps(std::string* out) = 0;
};

// ------------------------------------------------------------------ EC fans

#define EC_DATA_PORT 0x62
#define EC_SC_PORT   0x66
#define EC_SC_OBF    0x01
#define EC_SC_IBF    0x02
#define EC_CMD_READ  0x80
#define EC_CMD_WRITE 0x81

// ACPI embedded controller fan control — validated on the HP OmniBook 7
// 17-dc0xxx (Insyde BIOS). The register map is read from that machine's
// DSDT, so the backend only activates when the product name reports an
// OmniBook; unknown ECs are never probed.
class EcFans : public FanBackend {
 public:
  static bool Supported() {
    wchar_t product[128] = {};
    DWORD size = sizeof(product);
    if (RegGetValueW(HKEY_LOCAL_MACHINE,
                     L"HARDWARE\\DESCRIPTION\\System\\BIOS",
                     L"SystemProductName", RRF_RT_REG_SZ, nullptr, product,
                     &size) != ERROR_SUCCESS) {
      return false;
    }
    return wcsstr(product, L"OmniBook") != nullptr;
  }

  bool Init() {
    if (!pio_.Load(L"LpcACPIEC.bin")) return Fail(pio_.Error());
    mutex_ = CreateMutexW(nullptr, FALSE, L"Global\\Access_EC");
    return true;
  }

  const char* Name() const override { return "ec"; }
  const char* Error() const override { return err_; }
  int FanCount() const override { return kFanCount; }
  const char* FanLabel(int channel) const override {
    static const char* kLabels[] = {"Fan_1", "Fan_2"};
    return channel >= 0 && channel < kFanCount ? kLabels[channel] : "Fan";
  }
  bool HasRpm() const override { return false; }  // EC reports percent only

  int ReadPercent(int fan, int* pct) override {
    if (fan < 0 || fan >= kFanCount) return -1;
    MutexLock lock(mutex_);
    ULONG64 v = 0;
    if (RawRead(kFans[fan].read, &v)) return -1;
    *pct = (int)v;
    return 0;
  }

  int ReadRpm(int, int*) override { return -1; }

  int SetPercent(int fan, int pct) override {
    if (fan < 0 || fan >= kFanCount || pct < 0 || pct > 100) return -1;
    MutexLock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    if (RawWrite(kFans[fan].hold, hold | kHoldBit)) return -1;
    return RawWrite(kFans[fan].write, (ULONG64)pct);
  }

  int SetAuto(int fan) override {
    if (fan < 0 || fan >= kFanCount) return -1;
    MutexLock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    return RawWrite(kFans[fan].hold, hold & ~kHoldBit);
  }

  // Returns 1 when the manual-hold bit is set, 0 for firmware control,
  // -1 on error.
  int IsManual(int fan) override {
    if (fan < 0 || fan >= kFanCount) return -1;
    MutexLock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    return (hold & kHoldBit) ? 1 : 0;
  }

  // EC thermal-sensor block THS0..THSF lives at 0xA8..0xB7 (ECMB maps
  // there); entries reading 0x00 or >= 0x80 are unpopulated slots. Names
  // come from the DSDT's second Field(ECMB) block: CPUT/MSKT/AMBT/VDIN/PCHT.
  // VDIN is the DC-input area thermistor per Insyde convention.
  void AppendTemps(std::string* out) override {
    static const char* kThsName[16] = {"CPU_EC", "Skin",   "Ambient",
                                       "DC-In",  "PCH",    nullptr,
                                       nullptr,  nullptr,  nullptr,
                                       nullptr,  nullptr,  nullptr,
                                       nullptr,  nullptr,  nullptr,
                                       nullptr};
    MutexLock lock(mutex_);
    ULONG64 seen[16];
    int seenCount = 0;
    for (int i = 0; i < 16; i++) {
      ULONG64 v = 0;
      if (RawRead(0xA8 + i, &v) != 0 || v < 1 || v >= 0x80) continue;
      // Slots mirroring the same physical source read identically —
      // emit each distinct reading once.
      bool dup = false;
      for (int j = 0; j < seenCount; j++) dup |= seen[j] == v;
      if (dup) continue;
      seen[seenCount++] = v;
      char buf[24];
      if (kThsName[i]) {
        sprintf_s(buf, " %s=%llu", kThsName[i], v);
      } else {
        sprintf_s(buf, " Zone_%d=%llu", i, v);
      }
      *out += buf;
    }
  }

 private:
  struct FanRegs {
    ULONG64 read, write, hold;
  };
  // Offsets from the OmniBook's DSDT (Insyde EC region RAM_).
  static constexpr FanRegs kFans[] = {
      {0x95, 0x94, 0x93},  // fan 0: FAN1/FSW1/FSH1
      {0x83, 0x82, 0x81},  // fan 1: FAN2/FSW2/FSH2
  };
  static const ULONG64 kHoldBit = 0x10;
  static const int kFanCount = 2;

  bool Fail(const char* e) {
    strncpy_s(err_, e, _TRUNCATE);
    return false;
  }

  int PioRead(ULONG64 port, ULONG64* val) {
    ULONG64 in[1] = {port}, out[1] = {0};
    if (pio_.Exec("ioctl_pio_read", in, 1, out, 1)) return -1;
    *val = out[0];
    return 0;
  }
  int PioWrite(ULONG64 port, ULONG64 val) {
    ULONG64 in[2] = {port, val};
    return pio_.Exec("ioctl_pio_write", in, 2, nullptr, 0);
  }
  int WaitEc(int bit, int wantSet) {
    for (int i = 0; i < 2000; i++) {
      ULONG64 sc = 0;
      if (PioRead(EC_SC_PORT, &sc)) return -1;
      if (!!(sc & bit) == !!wantSet) return 0;
      Sleep(0);
    }
    return -1;
  }
  int RawRead(ULONG64 addr, ULONG64* val) {
    ULONG64 sc = 0;
    if (PioRead(EC_SC_PORT, &sc) == 0 && (sc & EC_SC_OBF)) {
      ULONG64 junk;
      PioRead(EC_DATA_PORT, &junk);
    }
    for (int i = 0; i < 3; i++) {
      if (WaitEc(EC_SC_IBF, 0)) continue;
      if (PioWrite(EC_SC_PORT, EC_CMD_READ)) continue;
      if (WaitEc(EC_SC_IBF, 0)) continue;
      if (PioWrite(EC_DATA_PORT, addr)) continue;
      if (WaitEc(EC_SC_OBF, 1)) continue;
      if (PioRead(EC_DATA_PORT, val) == 0) return 0;
    }
    return -1;
  }
  int RawWrite(ULONG64 addr, ULONG64 val) {
    ULONG64 sc = 0;
    if (PioRead(EC_SC_PORT, &sc) == 0 && (sc & EC_SC_OBF)) {
      ULONG64 junk;
      PioRead(EC_DATA_PORT, &junk);
    }
    for (int i = 0; i < 3; i++) {
      if (WaitEc(EC_SC_IBF, 0)) continue;
      if (PioWrite(EC_SC_PORT, EC_CMD_WRITE)) continue;
      if (WaitEc(EC_SC_IBF, 0)) continue;
      if (PioWrite(EC_DATA_PORT, addr)) continue;
      if (WaitEc(EC_SC_IBF, 0)) continue;
      if (PioWrite(EC_DATA_PORT, val)) continue;
      return 0;
    }
    return -1;
  }

  PawnIo pio_;
  HANDLE mutex_ = nullptr;
  char err_[128] = {};
};

// ----------------------------------------------------- Nuvoton Super I/O

// Nuvoton NCT6779D / NCT679x hardware monitor — the standard fan
// controller on desktop motherboards. Detection flow and register map
// follow LibreHardwareMonitor's Nct677X (same path FanControl uses):
//   config port 0x2E/0x4E, enter 0x87 0x87, chip ID regs 0x20/0x21,
//   hwmon LDN 0x0B, base address regs 0x60/0x61, vendor 0x5CA3.
// The LpcIO pawn module whitelists the config port plus all BARs it
// discovers via ioctl_find_bars, so hwmon access is range-checked.
class SuperIoFans : public FanBackend {
 public:
  bool Init() {
    if (!pio_.Load(L"LpcIO.bin")) return Fail(pio_.Error());
    // Same mutex LibreHardwareMonitor/FanControl hold around ISA access —
    // keeps us from racing them if both run at once.
    mutex_ = CreateMutexW(nullptr, FALSE,
                          L"Global\\Access_ISABUS.HTP.Method");
    MutexLock lock(mutex_);
    for (int slot = 0; slot < 2 && !chip_; slot++) Probe(slot);
    if (!chip_) return Fail("no Nuvoton super I/O");
    // Expose only channels that look populated: a live tach reading, or a
    // saturated tach while the firmware still runs the header (SmartFan
    // mode). Saturated tach + software mode is what unpopulated headers
    // report — skip those so the UI shows real fans only.
    for (int i = 0; i < chip_->fans; i++) {
      int rpm = 0;
      int status = Tach(i, &rpm);
      ULONG64 mode = 0;
      HwRead(kModeReg[i], &mode);
      if (status == 0 || (status == 1 && mode != 0)) channels_.push_back(i);
    }
    if (channels_.empty()) return Fail("no fan channels");
    return true;
  }

  const char* Name() const override { return chip_ ? chip_->name : "superio"; }
  const char* Error() const override { return err_; }
  int FanCount() const override { return (int)channels_.size(); }
  const char* FanLabel(int channel) const override {
    static __declspec(thread) char label[16];  // per pipe-worker buffer
    int i = channel >= 0 && channel < (int)channels_.size()
                ? channels_[channel]
                : channel;
    sprintf_s(label, "Fan_%d", i + 1);
    return label;
  }
  bool HasRpm() const override { return true; }

  int ReadPercent(int channel, int* pct) override {
    int ch = Chan(channel);
    if (ch < 0) return -1;
    MutexLock lock(mutex_);
    ULONG64 v = 0;
    if (HwRead(pwmOut_[ch], &v)) return -1;
    *pct = (int)((v * 100 + 127) / 255);
    return 0;
  }

  int ReadRpm(int channel, int* rpm) override {
    int ch = Chan(channel);
    if (ch < 0) return -1;
    MutexLock lock(mutex_);
    return Tach(ch, rpm) >= 0 ? 0 : -1;
  }

  int SetPercent(int channel, int pct) override {
    int ch = Chan(channel);
    if (ch < 0 || pct < 0 || pct > 100) return -1;
    MutexLock lock(mutex_);
    if (!saved_[ch]) {
      ULONG64 m = 0, p = 0;
      if (HwRead(kModeReg[ch], &m) || HwRead(kPwmCmdReg[ch], &p)) return -1;
      savedMode_[ch] = (BYTE)m;
      savedPwm_[ch] = (BYTE)p;
      saved_[ch] = true;
    }
    // Mode 0 = software (manual) control through the PWM command register.
    if (HwWrite(kModeReg[ch], 0)) return -1;
    return HwWrite(kPwmCmdReg[ch], (ULONG64)(pct * 255 + 50) / 100);
  }

  int SetAuto(int channel) override {
    int ch = Chan(channel);
    if (ch < 0) return -1;
    MutexLock lock(mutex_);
    if (saved_[ch]) {
      if (HwWrite(kModeReg[ch], savedMode_[ch])) return -1;
      if (HwWrite(kPwmCmdReg[ch], savedPwm_[ch])) return -1;
      saved_[ch] = false;
    }
    return 0;
  }

  int IsManual(int channel) override {
    int ch = Chan(channel);
    if (ch < 0) return -1;
    MutexLock lock(mutex_);
    ULONG64 m = 0;
    if (HwRead(kModeReg[ch], &m)) return -1;
    return m == 0 ? 1 : 0;
  }

  void AppendTemps(std::string* out) override {
    MutexLock lock(mutex_);
    const TempReg* temps = chip_->temps;
    ULONG64 seen[16];
    int seenCount = 0;
    for (int i = 0; temps[i].label; i++) {
      ULONG64 v = 0;
      // Temperatures are signed bytes; 0 and >= 0x7F are unpopulated or
      // invalid-source markers on this family.
      if (HwRead(temps[i].reg, &v) != 0 || v < 1 || v >= 0x7F) continue;
      // Boards routinely route one physical sensor to several monitor
      // slots, which then report identical values — emit each distinct
      // reading once so the UI shows no duplicates.
      bool dup = false;
      for (int j = 0; j < seenCount; j++) dup |= seen[j] == v;
      if (dup) continue;
      seen[seenCount++] = v;
      char buf[24];
      sprintf_s(buf, " %s=%llu", temps[i].label, v);
      *out += buf;
    }
  }

 private:
  struct TempReg {
    const char* label;
    USHORT reg;
  };
  struct ChipDef {
    BYTE id, rev, revMask;
    const char* name;
    int fans;          // fan/control channel count
    bool newPwmOut;    // newer PWM-out map (NCT6796DR+)
    const TempReg* temps;
  };

  // Hwmon registers are banked: high byte of the address selects the bank
  // (written to index 0x4E), low byte is the in-bank register.
  // Fan duty readout (0-255), manual PWM value, and mode (0 = software
  // control), one entry per channel.
  static const USHORT kPwmOutOld[7];
  static const USHORT kPwmOutNew[7];
  static const USHORT kPwmCmdReg[7];
  static const USHORT kModeReg[7];
  // 13-bit fan tach counters; RPM = 1.35e6 / count.
  static const USHORT kFanCountReg[7];
  static const int kCountMin = 0x15;
  static const int kCountMax = 0x1FFF;

  static const TempReg kTemps679x[];
  static const TempReg kTemps6779[];
  static const ChipDef kChips[];

  bool Fail(const char* e) {
    strncpy_s(err_, e, _TRUNCATE);
    return false;
  }

  int Chan(int index) const {
    return index >= 0 && index < (int)channels_.size() ? channels_[index] : -1;
  }

  int PortIn(ULONG64 port, ULONG64* v) {
    ULONG64 in[1] = {port}, out[1] = {0};
    if (pio_.Exec("ioctl_pio_inb", in, 1, out, 1)) return -1;
    *v = out[0];
    return 0;
  }
  int PortOut(ULONG64 port, ULONG64 val) {
    ULONG64 in[2] = {port, val};
    return pio_.Exec("ioctl_pio_outb", in, 2, nullptr, 0);
  }
  int SuperioIn(ULONG64 reg, ULONG64* v) {
    ULONG64 in[1] = {reg}, out[1] = {0};
    if (pio_.Exec("ioctl_superio_inb", in, 1, out, 1)) return -1;
    *v = out[0];
    return 0;
  }
  int SuperioInw(ULONG64 reg, ULONG64* v) {
    ULONG64 in[1] = {reg}, out[1] = {0};
    if (pio_.Exec("ioctl_superio_inw", in, 1, out, 1)) return -1;
    *v = out[0];
    return 0;
  }
  int SuperioOut(ULONG64 reg, ULONG64 val) {
    ULONG64 in[2] = {reg, val};
    return pio_.Exec("ioctl_superio_outb", in, 2, nullptr, 0);
  }

  // Hwmon-space access through the address/data port pair at base+5/+6.
  int HwRead(USHORT reg, ULONG64* v) {
    if (PortOut(hwmon_ + 5, 0x4E) || PortOut(hwmon_ + 6, reg >> 8) ||
        PortOut(hwmon_ + 5, reg & 0xFF) || PortIn(hwmon_ + 6, v)) {
      return -1;
    }
    return 0;
  }
  int HwWrite(USHORT reg, ULONG64 val) {
    if (PortOut(hwmon_ + 5, 0x4E) || PortOut(hwmon_ + 6, reg >> 8) ||
        PortOut(hwmon_ + 5, reg & 0xFF) || PortOut(hwmon_ + 6, val)) {
      return -1;
    }
    return 0;
  }

  // 13-bit tach counter: RPM = 1.35e6 / count. Returns 0 for a live
  // reading, 1 when the counter is saturated (fan stopped or header
  // empty), -2 when the count says no fan is wired, -1 on read error.
  int Tach(int ch, int* rpm) {
    ULONG64 hi = 0, lo = 0;
    if (HwRead(kFanCountReg[ch], &hi) || HwRead(kFanCountReg[ch] + 1, &lo)) {
      return -1;
    }
    int count = (int)((hi << 5) | (lo & 0x1F));
    if (count >= kCountMax) {
      *rpm = 0;
      return 1;
    }
    if (count < kCountMin) return -2;
    *rpm = 1350000 / count;
    return 0;
  }

  void Probe(int slot) {
    const ULONG64 regPort = slot == 0 ? 0x2E : 0x4E;
    ULONG64 in[1] = {(ULONG64)slot};
    if (pio_.Exec("ioctl_select_slot", in, 1, nullptr, 0)) return;
    // Winbond/Nuvoton/Fintek config mode: 0x87 twice to enter, 0xAA exit.
    PortOut(regPort, 0x87);
    PortOut(regPort, 0x87);
    ULONG64 id = 0, rev = 0;
    SuperioIn(0x20, &id);   // chip ID register
    SuperioIn(0x21, &rev);  // chip revision register
    const ChipDef* chip = nullptr;
    for (int i = 0; kChips[i].name; i++) {
      if (kChips[i].id == id && (rev & kChips[i].revMask) == kChips[i].rev) {
        chip = &kChips[i];
        break;
      }
    }
    if (!chip) {
      PortOut(regPort, 0xAA);
      return;
    }
    // Scan LDN base-address registers so the module whitelists the hwmon
    // port range; must run while still in config mode.
    pio_.Exec("ioctl_find_bars", nullptr, 0, nullptr, 0);
    SuperioOut(0x07, 0x0B);  // select hardware-monitor logical device
    ULONG64 a1 = 0, a2 = 0;
    SuperioInw(0x60, &a1);  // base address registers 0x60/0x61
    Sleep(1);
    SuperioInw(0x60, &a2);
    // Config reg 0x28 bit 4 = hwmon I/O space lock; clear it on 679xD.
    ULONG64 lockReg = 0;
    if (SuperioIn(0x28, &lockReg) == 0 && (lockReg & 0x10)) {
      SuperioOut(0x28, lockReg & ~0x10ULL);
    }
    PortOut(regPort, 0xAA);
    USHORT base = (USHORT)a1;
    if (a1 != a2 || base < 0x100 || (base & 0xF007) != 0) return;
    // Confirm through the hwmon space: bank 8 reg 0x4F + bank 0 reg 0x4F
    // hold the Nuvoton vendor ID 0x5CA3.
    ULONG64 hi = 0, lo = 0;
    hwmon_ = base;
    if (HwRead(0x804F, &hi) || HwRead(0x004F, &lo) ||
        ((hi << 8) | lo) != 0x5CA3) {
      hwmon_ = 0;
      return;
    }
    chip_ = chip;
    pwmOut_ = chip->newPwmOut ? kPwmOutNew : kPwmOutOld;
  }

  PawnIo pio_;
  HANDLE mutex_ = nullptr;
  const ChipDef* chip_ = nullptr;
  const USHORT* pwmOut_ = nullptr;
  USHORT hwmon_ = 0;
  std::vector<int> channels_;  // exposed index -> chip channel
  bool saved_[7] = {};
  BYTE savedMode_[7] = {};
  BYTE savedPwm_[7] = {};
  char err_[128] = {};
};

const USHORT SuperIoFans::kPwmOutOld[7] = {0x001, 0x003, 0x011, 0x013,
                                           0x015, 0x017, 0x029};
const USHORT SuperIoFans::kPwmOutNew[7] = {0x001, 0x003, 0x011, 0x013,
                                           0x015, 0xA09, 0xB09};
const USHORT SuperIoFans::kPwmCmdReg[7] = {0x109, 0x209, 0x309, 0x809,
                                           0x909, 0xA09, 0xB09};
const USHORT SuperIoFans::kModeReg[7] = {0x102, 0x202, 0x302, 0x802,
                                         0x902, 0xA02, 0xB02};
const USHORT SuperIoFans::kFanCountReg[7] = {0x4B0, 0x4B2, 0x4B4, 0x4B6,
                                             0x4B8, 0x4BA, 0x4CC};

// Temperature inputs for the NCT6791D-6799D family. CPUTIN is the socket
// sensor (labeled CPU_socket so it can never collide with a CPU die temp
// from another source), SYSTIN = motherboard, AUXTINn = board auxiliaries.
// Primary/canonical names come first — on boards that mirror one physical
// source into several slots, the first label wins the dedupe.
const SuperIoFans::TempReg SuperIoFans::kTemps679x[] = {
    {"CPU_socket", 0x075}, {"Motherboard", 0x077}, {"CPU_PECI", 0x073},
    {"Aux_0", 0x079},      {"Aux_1", 0x07B},       {"Aux_2", 0x07D},
    {"Aux_3", 0x4A0},      {"Aux_4", 0x027},       {nullptr, 0}};
const SuperIoFans::TempReg SuperIoFans::kTemps6779[] = {
    {"CPU_socket", 0x073}, {"Motherboard", 0x075}, {"CPU_PECI", 0x027},
    {"Aux_0", 0x077},      {"Aux_1", 0x079},       {"Aux_2", 0x07B},
    {"Aux_3", 0x150},      {nullptr, 0}};

// Chip-ID/revision table (config regs 0x20/0x21) for the family whose
// register map above applies. Unknown IDs are left alone.
const SuperIoFans::ChipDef SuperIoFans::kChips[] = {
    {0xC5, 0x60, 0xF0, "nct6779d", 5, false, kTemps6779},
    {0xC8, 0x03, 0xFF, "nct6791d", 6, false, kTemps679x},
    {0xC9, 0x11, 0xFF, "nct6792d", 6, false, kTemps679x},
    {0xC9, 0x13, 0xFF, "nct6792da", 6, false, kTemps679x},
    {0xD1, 0x21, 0xFF, "nct6793d", 6, false, kTemps679x},
    {0xD3, 0x52, 0xFF, "nct6795d", 6, false, kTemps679x},
    {0xD4, 0x23, 0xFF, "nct6796d", 6, false, kTemps679x},
    {0xD4, 0x2A, 0xFF, "nct6796dr", 7, true, kTemps679x},
    {0xD4, 0x51, 0xFF, "nct6797d", 7, true, kTemps679x},
    {0xD4, 0x2B, 0xFF, "nct6798d", 7, true, kTemps679x},
    {0xD8, 0x02, 0xFF, "nct6799d", 7, true, kTemps679x},
    {0xD8, 0x06, 0xFF, "nct6701d", 7, false, kTemps679x},
    {0, 0, 0, nullptr, 0, false, nullptr}};

// ------------------------------------------------------------- CPU temp

// Reads the Intel package temperature via the PawnIO IntelMSR module:
// IA32_TEMPERATURE_TARGET (0x1A2) bits 23:16 -> TjMax,
// IA32_PACKAGE_THERM_STATUS (0x1B1) bit 31 = valid, bits 22:16 = readout.
// Package temp = TjMax - readout.
// Intel-only MSRs — never executed on AMD/unknown CPUs.
class CpuTemp {
 public:
  static bool Supported() {
    wchar_t vendor[64] = {};
    DWORD size = sizeof(vendor);
    if (RegGetValueW(HKEY_LOCAL_MACHINE,
                     L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                     L"VendorIdentifier", RRF_RT_REG_SZ, nullptr, vendor,
                     &size) != ERROR_SUCCESS) {
      return false;
    }
    return wcsstr(vendor, L"GenuineIntel") != nullptr;
  }

  bool Init() {
    if (!pio_.Load(L"IntelMSR.bin")) return false;
    ULONG64 tjField = 0;
    if (ReadMsr(0x1A2, &tjField)) return false;
    tjMax_ = (int)((tjField >> 16) & 0xFF);
    if (tjMax_ <= 0 || tjMax_ > 130) tjMax_ = 100;  // sane default
    return true;
  }

  // Returns package temp in C, or -1 on error.
  int Read() {
    ULONG64 s = 0;
    if (ReadMsr(0x1B1, &s)) return -1;
    if (!(s & (1ULL << 31))) return -1;  // reading not valid
    return tjMax_ - (int)((s >> 16) & 0x7F);
  }

 private:
  int ReadMsr(ULONG64 msr, ULONG64* val) {
    ULONG64 in[1] = {msr}, out[1] = {0};
    if (pio_.Exec("ioctl_read_msr", in, 1, out, 1)) return -1;
    *val = out[0];
    return 0;
  }

  PawnIo pio_;
  int tjMax_ = 100;
};

// ------------------------------------------------------------- SSD temp

// NVMe composite temperature via StorageDeviceTemperatureProperty.
// Returns Celsius, or -1 when unavailable. Works for any storage device
// type, not just NVMe — the driver stack fills it in.
static int SsdTemp(int drive) {
  wchar_t path[32];
  swprintf_s(path, L"\\\\.\\PhysicalDrive%d", drive);
  // No access rights needed — the query goes through the storage stack.
  HANDLE h = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                         OPEN_EXISTING, 0, nullptr);
  if (h == INVALID_HANDLE_VALUE) return -1;

  STORAGE_PROPERTY_QUERY q{};
  q.PropertyId = StorageDeviceTemperatureProperty;
  q.QueryType = PropertyStandardQuery;
  BYTE buf[512] = {};
  DWORD ret = 0;
  int temp = -1;
  if (DeviceIoControl(h, IOCTL_STORAGE_QUERY_PROPERTY, &q, sizeof(q), buf,
                      sizeof(buf), &ret, nullptr)) {
    // Response: STORAGE_TEMPERATURE_DATA_DESCRIPTOR + STORAGE_TEMPERATURE_INFO
    // entries; Temperature is a signed short in Celsius, 0x8000 = not reported.
    auto* hdr = reinterpret_cast<STORAGE_TEMPERATURE_DATA_DESCRIPTOR*>(buf);
    if (ret >= sizeof(STORAGE_TEMPERATURE_DATA_DESCRIPTOR) &&
        hdr->InfoCount >= 1) {
      SHORT t = hdr->TemperatureInfo[0].Temperature;
      if (t != (SHORT)STORAGE_TEMPERATURE_VALUE_NOT_REPORTED && t > 0 &&
          t < 150) {
        temp = t;
      }
    }
  }
  CloseHandle(h);
  return temp;
}

// ------------------------------------------------------- pipe server layer

static std::vector<std::unique_ptr<FanBackend>> g_backends;
// Merged index space: global fan index -> (backend, backend channel).
static std::vector<std::pair<FanBackend*, int>> g_fans;
static CpuTemp g_temp;
static volatile bool g_running = true;
// Tick count of the last pipe command; the watchdog releases manual fan
// holds when this goes stale (app crashed or exited).
static volatile ULONGLONG g_lastCmd = 0;

static void EventLog(const char* msg);

// Probes all backends and builds the merged fan map. Super I/O first —
// desktop boards answer with real chip IDs; the EC backend additionally
// checks the product name so it never pokes an unknown controller.
static void DetectBackends() {
  auto sio = std::make_unique<SuperIoFans>();
  if (sio->Init()) {
    g_backends.push_back(std::move(sio));
  } else {
    EventLog(sio->Error());
  }
  if (EcFans::Supported()) {
    auto ec = std::make_unique<EcFans>();
    if (ec->Init()) {
      g_backends.push_back(std::move(ec));
    } else {
      EventLog(ec->Error());
    }
  }
  for (auto& b : g_backends) {
    for (int i = 0; i < b->FanCount(); i++) {
      g_fans.push_back({b.get(), i});
    }
  }
}

static std::string Handle(const std::string& line) {
  g_lastCmd = GetTickCount64();
  char cmd[16], a[8], b[8];
  int n = sscanf_s(line.c_str(), "%15s %7s %7s", cmd, (unsigned)sizeof(cmd), a,
                   (unsigned)sizeof(a), b, (unsigned)sizeof(b));
  if (n <= 0) return "err empty";
  if (!strcmp(cmd, "ping")) return "pong";
  if (!strcmp(cmd, "backend")) {
    if (g_backends.empty()) return "ok none";
    std::string out = "ok";
    for (auto& b : g_backends) out += std::string(" ") + b->Name();
    return out;
  }
  if (!strcmp(cmd, "caps")) {
    int flags = 0;
    for (auto& b : g_backends) {
      if (b->HasRpm()) flags |= 1;
    }
    char buf[16];
    sprintf_s(buf, "ok %d", flags);
    return buf;
  }
  if (!strcmp(cmd, "list")) {
    char buf[32];
    sprintf_s(buf, "ok %d", (int)g_fans.size());
    return buf;
  }
  int fan = (n >= 2) ? atoi(a) : -1;
  FanBackend* be = nullptr;
  int ch = -1;
  if (fan >= 0 && fan < (int)g_fans.size()) {
    be = g_fans[fan].first;
    ch = g_fans[fan].second;
  }
  if (!strcmp(cmd, "name") && n == 2 && be) {
    std::string out = "ok ";
    out += be->FanLabel(ch);
    return out;
  }
  if (!strcmp(cmd, "read") && n == 2 && be) {
    int pct = 0;
    if (be->ReadPercent(ch, &pct) == 0) {
      char buf[32];
      sprintf_s(buf, "ok %d", pct);
      return buf;
    }
    return "err hw";
  }
  if (!strcmp(cmd, "rpm") && n == 2 && be) {
    int rpm = 0;
    if (be->ReadRpm(ch, &rpm) == 0) {
      char buf[32];
      sprintf_s(buf, "ok %d", rpm);
      return buf;
    }
    return "err rpm";
  }
  if (!strcmp(cmd, "set") && n == 3 && be)
    return be->SetPercent(ch, atoi(b)) == 0 ? "ok" : "err hw";
  if (!strcmp(cmd, "auto") && n == 2 && be)
    return be->SetAuto(ch) == 0 ? "ok" : "err hw";
  if (!strcmp(cmd, "mode") && n == 2 && be) {
    int m = be->IsManual(ch);
    if (m >= 0) {
      char buf[16];
      sprintf_s(buf, "ok %d", m);
      return buf;
    }
    return "err hw";
  }
  if (!strcmp(cmd, "temp")) {
    int t = g_temp.Read();
    if (t >= 0) {
      char buf[16];
      sprintf_s(buf, "ok %d", t);
      return buf;
    }
    return "err sensor";
  }
  // "temps" -> "ok <label>=<celsius> [<label>=<celsius> ...]"
  if (!strcmp(cmd, "temps")) {
    std::string out = "ok";
    int c = g_temp.Read();
    if (c >= 0) out += " CPU=" + std::to_string(c);
    for (auto& b : g_backends) b->AppendTemps(&out);
    for (int d = 0; d < 8; d++) {
      int t = SsdTemp(d);
      if (t > 0) {
        char buf[24];
        if (d == 0)
          sprintf_s(buf, " SSD=%d", t);
        else
          sprintf_s(buf, " SSD_%d=%d", d, t);
        out += buf;
      }
    }
    return out;
  }
  return "err badcmd";
}

// Clears manual holds when the app goes quiet for ~30s. The app's poll
// loop issues commands every few seconds while it runs, so this only
// fires when the app is gone — firmware control is the safe fallback.
static DWORD WINAPI Watchdog(LPVOID) {
  const ULONGLONG kTimeoutMs = 30000;
  while (g_running) {
    Sleep(5000);
    if (GetTickCount64() - g_lastCmd > kTimeoutMs) {
      for (auto& f : g_fans) {
        if (f.first->IsManual(f.second) == 1) f.first->SetAuto(f.second);
      }
    }
  }
  return 0;
}

static DWORD WINAPI PipeWorker(LPVOID hp) {
  HANDLE pipe = (HANDLE)hp;
  char buf[256];
  DWORD n;
  while (g_running &&
         ReadFile(pipe, buf, sizeof(buf) - 1, &n, nullptr) && n > 0) {
    buf[n] = 0;
    std::string reply = Handle(buf) + "\n";
    DWORD w;
    if (!WriteFile(pipe, reply.c_str(), (DWORD)reply.size(), &w, nullptr))
      break;
    FlushFileBuffers(pipe);
  }
  DisconnectNamedPipe(pipe);
  CloseHandle(pipe);
  return 0;
}

static DWORD WINAPI PipeServer(LPVOID) {
  // SD: SYSTEM+Admins full, Everyone read/write — the unelevated app must
  // connect. The pipe only exposes the narrow command set above.
  SECURITY_DESCRIPTOR sd;
  InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION);
  SetSecurityDescriptorDacl(&sd, TRUE, nullptr, FALSE);  // permissive DACL
  SECURITY_ATTRIBUTES sa{sizeof(sa), &sd, FALSE};

  while (g_running) {
    HANDLE pipe = CreateNamedPipeW(
        L"\\\\.\\pipe\\netturbine_fan", PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES, 4096, 4096, 0, &sa);
    if (pipe == INVALID_HANDLE_VALUE) return 1;
    if (ConnectNamedPipe(pipe, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED) {
      HANDLE t = CreateThread(nullptr, 0, PipeWorker, pipe, 0, nullptr);
      if (t) CloseHandle(t);
      else { DisconnectNamedPipe(pipe); CloseHandle(pipe); }
    } else {
      CloseHandle(pipe);
    }
  }
  return 0;
}

// ------------------------------------------------------------ service glue

static SERVICE_STATUS_HANDLE g_ss;
static HANDLE g_serverThread;
static HANDLE g_stopEvent;

static DWORD WINAPI ServiceHandler(DWORD ctrl, DWORD, LPVOID, LPVOID) {
  if (ctrl == SERVICE_CONTROL_STOP || ctrl == SERVICE_CONTROL_SHUTDOWN) {
    SERVICE_STATUS s{SERVICE_WIN32_OWN_PROCESS, SERVICE_STOP_PENDING, 0, 0};
    SetServiceStatus(g_ss, &s);
    g_running = false;
    SetEvent(g_stopEvent);
    return 0;
  }
  return NO_ERROR;
}

static void ServiceRun() {
  DetectBackends();
  if (CpuTemp::Supported()) g_temp.Init();  // optional sensor
  g_stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_lastCmd = GetTickCount64();  // arm watchdog: clear stale holds if
                                 // no app connects within the timeout
  g_serverThread = CreateThread(nullptr, 0, PipeServer, nullptr, 0, nullptr);
  CreateThread(nullptr, 0, Watchdog, nullptr, 0, nullptr);
}

static void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_ss = RegisterServiceCtrlHandlerExW(L"NetturbineFanHelper", ServiceHandler,
                                       nullptr);
  SERVICE_STATUS s{SERVICE_WIN32_OWN_PROCESS, SERVICE_START_PENDING, 0, 0};
  SetServiceStatus(g_ss, &s);

  ServiceRun();
  char log[64];
  sprintf_s(log, "fan_helper: %d fans, %d backends", (int)g_fans.size(),
            (int)g_backends.size());
  EventLog(log);

  s.dwCurrentState = SERVICE_RUNNING;
  s.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
  SetServiceStatus(g_ss, &s);

  WaitForSingleObject(g_stopEvent, INFINITE);
  g_running = false;
  WaitForSingleObject(g_serverThread, 5000);

  s.dwCurrentState = SERVICE_STOPPED;
  SetServiceStatus(g_ss, &s);
}

static void EventLog(const char* msg) {
  // services have no console — write to a log file next to the exe
  wchar_t dir[MAX_PATH];
  GetModuleFileNameW(nullptr, dir, MAX_PATH);
  wchar_t* slash = wcsrchr(dir, L'\\');
  if (slash) *slash = 0;
  std::wstring p = std::wstring(dir) + L"\\fan_helper.log";
  FILE* f;
  if (_wfopen_s(&f, p.c_str(), L"a") == 0 && f) {
    fprintf(f, "%s\n", msg);
    fclose(f);
  }
}

int wmain(int argc, wchar_t** argv) {
  if (argc > 1 && !wcscmp(argv[1], L"install")) {
    wchar_t self[MAX_PATH];
    GetModuleFileNameW(nullptr, self, MAX_PATH);
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CREATE_SERVICE);
    if (!scm) { fprintf(stderr, "SCM: %lu\n", GetLastError()); return 2; }
    std::wstring cmd = L"\"" + std::wstring(self) + L"\"";
    SC_HANDLE svc = CreateServiceW(scm, L"NetturbineFanHelper",
                                 L"Netturbine Fan Helper",
                                 SERVICE_ALL_ACCESS, SERVICE_WIN32_OWN_PROCESS,
                                 SERVICE_AUTO_START, SERVICE_ERROR_NORMAL,
                                 cmd.c_str(), nullptr, nullptr, nullptr,
                                 nullptr, nullptr);
    if (!svc) { fprintf(stderr, "CreateService: %lu\n", GetLastError()); return 2; }
    StartServiceW(svc, 0, nullptr);
    CloseServiceHandle(svc);
    CloseServiceHandle(scm);
    printf("service installed and started\n");
    return 0;
  }
  if (argc > 1 && !wcscmp(argv[1], L"uninstall")) {
    SC_HANDLE scm = OpenSCManagerW(nullptr, nullptr, SC_MANAGER_CONNECT);
    SC_HANDLE svc = OpenServiceW(scm, L"NetturbineFanHelper", SERVICE_STOP | DELETE);
    if (svc) {
      SERVICE_STATUS s;
      ControlService(svc, SERVICE_CONTROL_STOP, &s);
      DeleteService(svc);
      CloseServiceHandle(svc);
    }
    if (scm) CloseServiceHandle(scm);
    printf("service removed\n");
    return 0;
  }
  if (argc > 1 && !wcscmp(argv[1], L"console")) {
    DetectBackends();
    if (CpuTemp::Supported() && !g_temp.Init()) {
      fprintf(stderr, "CPU temp sensor unavailable\n");
    }
    std::string names;
    for (auto& b : g_backends) {
      if (!names.empty()) names += "+";
      names += b->Name();
    }
    printf("backends: %s, %d fans\n", names.empty() ? "none" : names.c_str(),
           (int)g_fans.size());
    printf("serving \\\\.\\pipe\\netturbine_fan\n");
    g_lastCmd = GetTickCount64();
    CreateThread(nullptr, 0, Watchdog, nullptr, 0, nullptr);
    PipeServer(nullptr);
    return 0;
  }
  SERVICE_TABLE_ENTRYW tbl[] = {
      {(LPWSTR)L"NetturbineFanHelper", ServiceMain}, {nullptr, nullptr}};
  if (!StartServiceCtrlDispatcherW(tbl) && GetLastError() ==
      ERROR_FAILED_SERVICE_CONTROLLER_CONNECT) {
    fprintf(stderr, "usage: fan_helper [install|uninstall|console]\n");
    return 1;
  }
  return 0;
}
