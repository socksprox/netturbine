// fan_helper — elevated helper for netturbine fan control.
//
// Talks to the embedded controller through PawnIO (LpcACPIEC.bin module,
// ports 0x62/0x66), serialized via the global "Access_EC" mutex so it does
// not race acpi.sys's own EC driver.
//
// Serves named pipe \\.\pipe\netturbine_fan with a line-based protocol:
//   ping                -> "pong"
//   list                -> "ok <n>"            (fan count)
//   read <fan>          -> "ok <percent>"      (0-100)
//   mode <fan>          -> "ok <0|1>"          (0 auto, 1 manual hold)
//   set <fan> <pct>     -> "ok"                (holds fan at pct)
//   auto <fan>          -> "ok"                (firmware control)
//   temp                -> "ok <celsius>"      (CPU package temp)
//   temps               -> "ok L=c [L=c ...]"  (all temp sensors; '_' = space)
//   anything else       -> "err <msg>"
//
// Modes:
//   fan_helper.exe install    — register + start the Windows service
//   fan_helper.exe uninstall  — stop + remove the service
//   fan_helper.exe console    — run the pipe server in the foreground
//   (no args, SCM-launched)   — service entry point

#include <windows.h>
#include <winioctl.h>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

// ---------------------------------------------------------------- EC layer

#define EC_DATA_PORT 0x62
#define EC_SC_PORT   0x66
#define EC_SC_OBF    0x01
#define EC_SC_IBF    0x02
#define EC_CMD_READ  0x80
#define EC_CMD_WRITE 0x81

typedef HRESULT(STDAPICALLTYPE* pawnio_open_fn)(PHANDLE);
typedef HRESULT(STDAPICALLTYPE* pawnio_load_fn)(HANDLE, const UCHAR*, SIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_execute_fn)(HANDLE, PCSTR,
                                                 const ULONG64*, SIZE_T,
                                                 PULONG64, SIZE_T, PSIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_close_fn)(HANDLE);

struct FanRegs { ULONG64 read, write, hold; };
// Offsets from this machine's DSDT (HP OmniBook 7, Insyde EC region RAM_).
static const FanRegs kFans[] = {
    {0x95, 0x94, 0x93},  // fan 0: FAN1/FSW1/FSH1
    {0x83, 0x82, 0x81},  // fan 1: FAN2/FSW2/FSH2
};
static const ULONG64 kHoldBit = 0x10;
static const int kFanCount = 2;

class Ec {
 public:
  bool Init() {
    lib_ = LoadLibraryW(L"PawnIOLib.dll");  // resolves via PATH / installed dir
    if (!lib_) lib_ = LoadLibraryW(L"C:\\Program Files\\PawnIO\\PawnIOLib.dll");
    if (!lib_) return Fail("PawnIOLib.dll not found");
    exec_ = (pawnio_execute_fn)GetProcAddress(lib_, "pawnio_execute");
    auto open = (pawnio_open_fn)GetProcAddress(lib_, "pawnio_open");
    auto load = (pawnio_load_fn)GetProcAddress(lib_, "pawnio_load");
    close_ = (pawnio_close_fn)GetProcAddress(lib_, "pawnio_close");
    if (!exec_ || !open || !load || !close_) return Fail("PawnIOLib exports");

    if (FAILED(open(&pio_)) || !pio_) return Fail("pawnio_open");

    wchar_t dir[MAX_PATH];
    GetModuleFileNameW(nullptr, dir, MAX_PATH);
    wchar_t* slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;
    std::wstring blobPath = std::wstring(dir) + L"\\LpcACPIEC.bin";
    HANDLE f = CreateFileW(blobPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) {
      blobPath = L"C:\\Users\\user\\Code\\netturbine\\windows\\tools\\"
                 L"pawnio_modules\\LpcACPIEC.bin";
      f = CreateFileW(blobPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                      OPEN_EXISTING, 0, nullptr);
      if (f == INVALID_HANDLE_VALUE) return Fail("LpcACPIEC.bin not found");
    }
    DWORD sz = GetFileSize(f, nullptr);
    std::vector<BYTE> blob(sz);
    DWORD rd = 0;
    ReadFile(f, blob.data(), sz, &rd, nullptr);
    CloseHandle(f);
    if (FAILED(load(pio_, blob.data(), blob.size()))) return Fail("pawnio_load");

    mutex_ = CreateMutexW(nullptr, FALSE, L"Global\\Access_EC");
    return true;
  }

  ~Ec() {
    if (mutex_) CloseHandle(mutex_);
    if (pio_ && close_) close_(pio_);
    if (lib_) FreeLibrary(lib_);
  }

  const char* Error() const { return err_; }

  int Read(int fan, ULONG64* v) {
    if (fan < 0 || fan >= kFanCount) return -1;
    Lock lock(mutex_);
    return RawRead(kFans[fan].read, v);
  }

  int SetPercent(int fan, int pct) {
    if (fan < 0 || fan >= kFanCount || pct < 0 || pct > 100) return -1;
    Lock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    if (RawWrite(kFans[fan].hold, hold | kHoldBit)) return -1;
    return RawWrite(kFans[fan].write, (ULONG64)pct);
  }

  int SetAuto(int fan) {
    if (fan < 0 || fan >= kFanCount) return -1;
    Lock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    return RawWrite(kFans[fan].hold, hold & ~kHoldBit);
  }

  // Read an arbitrary EC RAM register. Used for the thermal-sensor block.
  int ReadReg(ULONG64 addr, ULONG64* v) {
    Lock lock(mutex_);
    return RawRead(addr, v);
  }

  // Returns 1 when the manual-hold bit is set, 0 for firmware control,
  // -1 on error.
  int IsManual(int fan) {
    if (fan < 0 || fan >= kFanCount) return -1;
    Lock lock(mutex_);
    ULONG64 hold = 0;
    if (RawRead(kFans[fan].hold, &hold)) return -1;
    return (hold & kHoldBit) ? 1 : 0;
  }

 private:
  struct Lock {
    explicit Lock(HANDLE m) : m_(m) {
      if (m_) WaitForSingleObject(m_, 3000);
    }
    ~Lock() { if (m_) ReleaseMutex(m_); }
    HANDLE m_;
  };

  bool Fail(const char* e) { strncpy_s(err_, e, _TRUNCATE); return false; }

  int PioRead(ULONG64 port, ULONG64* val) {
    ULONG64 in[1] = {port}, out[1] = {0};
    SIZE_T ret = 0;
    if (FAILED(exec_(pio_, "ioctl_pio_read", in, 1, out, 1, &ret))) return -1;
    *val = out[0];
    return 0;
  }
  int PioWrite(ULONG64 port, ULONG64 val) {
    ULONG64 in[2] = {port, val}, out[1];
    SIZE_T ret = 0;
    return FAILED(exec_(pio_, "ioctl_pio_write", in, 2, out, 0, &ret)) ? -1 : 0;
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

  HMODULE lib_ = nullptr;
  HANDLE pio_ = nullptr;
  HANDLE mutex_ = nullptr;
  pawnio_execute_fn exec_ = nullptr;
  pawnio_close_fn close_ = nullptr;
  char err_[128] = {};
};

// ------------------------------------------------------------- CPU temp

// Reads the Intel package temperature via the PawnIO IntelMSR module:
// IA32_TEMPERATURE_TARGET (0x1A2) bits 23:16 -> TjMax,
// IA32_PACKAGE_THERM_STATUS (0x1B1) bit 31 = valid, bits 22:16 = readout.
// Package temp = TjMax - readout.
class CpuTemp {
 public:
  bool Init() {
    HMODULE lib = LoadLibraryW(L"PawnIOLib.dll");
    if (!lib)
      lib = LoadLibraryW(L"C:\\Program Files\\PawnIO\\PawnIOLib.dll");
    if (!lib) return false;
    exec_ = (pawnio_execute_fn)GetProcAddress(lib, "pawnio_execute");
    auto open = (pawnio_open_fn)GetProcAddress(lib, "pawnio_open");
    auto load = (pawnio_load_fn)GetProcAddress(lib, "pawnio_load");
    close_ = (pawnio_close_fn)GetProcAddress(lib, "pawnio_close");
    if (!exec_ || !open || !load || !close_) return false;
    if (FAILED(open(&pio_)) || !pio_) return false;

    wchar_t dir[MAX_PATH];
    GetModuleFileNameW(nullptr, dir, MAX_PATH);
    wchar_t* slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;
    std::wstring blobPath = std::wstring(dir) + L"\\IntelMSR.bin";
    HANDLE f = CreateFileW(blobPath.c_str(), GENERIC_READ, FILE_SHARE_READ,
                           nullptr, OPEN_EXISTING, 0, nullptr);
    if (f == INVALID_HANDLE_VALUE) {
      blobPath = L"C:\\Users\\user\\Code\\netturbine\\windows\\tools\\"
                 L"pawnio_modules\\IntelMSR.bin";
      f = CreateFileW(blobPath.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                      OPEN_EXISTING, 0, nullptr);
      if (f == INVALID_HANDLE_VALUE) return false;
    }
    DWORD sz = GetFileSize(f, nullptr);
    std::vector<BYTE> blob(sz);
    DWORD rd = 0;
    ReadFile(f, blob.data(), sz, &rd, nullptr);
    CloseHandle(f);
    if (FAILED(load(pio_, blob.data(), blob.size()))) return false;

    ULONG64 tjField = 0;
    if (ReadMsr(0x1A2, &tjField)) return false;
    tjMax_ = (int)((tjField >> 16) & 0xFF);
    if (tjMax_ <= 0 || tjMax_ > 130) tjMax_ = 100;  // sane default
    return true;
  }

  ~CpuTemp() {
    if (pio_ && close_) close_(pio_);
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
    SIZE_T ret = 0;
    if (FAILED(exec_(pio_, "ioctl_read_msr", in, 1, out, 1, &ret))) return -1;
    *val = out[0];
    return 0;
  }

  HANDLE pio_ = nullptr;
  pawnio_execute_fn exec_ = nullptr;
  pawnio_close_fn close_ = nullptr;
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

static Ec g_ec;
static CpuTemp g_temp;
static volatile bool g_running = true;

static std::string Handle(const std::string& line) {
  char cmd[16], a[8], b[8];
  int n = sscanf_s(line.c_str(), "%15s %7s %7s", cmd, (unsigned)sizeof(cmd), a,
                   (unsigned)sizeof(a), b, (unsigned)sizeof(b));
  if (n <= 0) return "err empty";
  if (!strcmp(cmd, "ping")) return "pong";
  if (!strcmp(cmd, "list")) {
    char buf[32];
    sprintf_s(buf, "ok %d", kFanCount);
    return buf;
  }
  if (!strcmp(cmd, "read") && n == 2) {
    ULONG64 v;
    if (g_ec.Read(atoi(a), &v) == 0) {
      char buf[32];
      sprintf_s(buf, "ok %llu", v);
      return buf;
    }
    return "err ec";
  }
  if (!strcmp(cmd, "set") && n == 3)
    return g_ec.SetPercent(atoi(a), atoi(b)) == 0 ? "ok" : "err ec";
  if (!strcmp(cmd, "auto") && n == 2)
    return g_ec.SetAuto(atoi(a)) == 0 ? "ok" : "err ec";
  if (!strcmp(cmd, "mode") && n == 2) {
    int m = g_ec.IsManual(atoi(a));
    if (m >= 0) {
      char buf[16];
      sprintf_s(buf, "ok %d", m);
      return buf;
    }
    return "err ec";
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
  // EC thermal-sensor block THS0..THSF lives at 0xA8..0xB7 (ECMB maps there);
  // entries reading 0x00 or >= 0x80 are unpopulated slots.
  if (!strcmp(cmd, "temps")) {
    std::string out = "ok";
    int c = g_temp.Read();
    if (c >= 0) out += " CPU=" + std::to_string(c);
    for (int i = 0; i < 16; i++) {
      ULONG64 v = 0;
      if (g_ec.ReadReg(0xA8 + i, &v) == 0 && v >= 1 && v < 0x80) {
        char buf[24];
        sprintf_s(buf, " Zone_%d=%llu", i, v);
        out += buf;
      }
    }
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

static void WINAPI ServiceMain(DWORD, LPWSTR*) {
  g_ss = RegisterServiceCtrlHandlerExW(L"NetturbineFanHelper", ServiceHandler,
                                       nullptr);
  SERVICE_STATUS s{SERVICE_WIN32_OWN_PROCESS, SERVICE_START_PENDING, 0, 0};
  SetServiceStatus(g_ss, &s);

  if (!g_ec.Init()) {
    s.dwCurrentState = SERVICE_STOPPED;
    s.dwWin32ExitCode = 2;
    SetServiceStatus(g_ss, &s);
    return;
  }
  g_temp.Init();  // optional — temp reports "err sensor" when unavailable
  g_stopEvent = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  g_serverThread = CreateThread(nullptr, 0, PipeServer, nullptr, 0, nullptr);

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
    if (!g_ec.Init()) { fprintf(stderr, "EC init: %s\n", g_ec.Error()); return 2; }
    if (!g_temp.Init()) fprintf(stderr, "CPU temp sensor unavailable\n");
    printf("EC ready, serving \\\\.\\pipe\\netturbine_fan\n");
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
