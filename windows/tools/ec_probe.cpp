// ec_probe — read embedded-controller registers via PawnIO (LpcACPIEC.bin).
// Implements the ACPI EC I/O protocol over ports 0x62/0x66, serialized
// against the OS EC driver via the global "\BaseNamedObjects\Access_EC"
// mutex (Global\Access_EC in user mode).
//
// Usage: ec_probe.exe [read <offset>]...
//        ec_probe.exe dump            — read all candidate fan registers
// Offsets may be decimal or 0x-prefixed hex.

#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#define EC_DATA_PORT 0x62
#define EC_SC_PORT   0x66
#define EC_SC_OBF    0x01  // output buffer full
#define EC_SC_IBF    0x02  // input buffer full
#define EC_CMD_READ  0x80
#define EC_CMD_WRITE 0x81

typedef HRESULT(STDAPICALLTYPE* pawnio_open_fn)(PHANDLE);
typedef HRESULT(STDAPICALLTYPE* pawnio_load_fn)(HANDLE, const UCHAR*, SIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_execute_fn)(HANDLE, PCSTR, const ULONG64*,
                                                 SIZE_T, PULONG64, SIZE_T,
                                                 PSIZE_T);
typedef HRESULT(STDAPICALLTYPE* pawnio_close_fn)(HANDLE);

static pawnio_execute_fn g_exec;
static HANDLE g_pio;

static int PioRead(ULONG64 port, ULONG64* val) {
  ULONG64 in[1] = {port}, out[1] = {0};
  SIZE_T ret = 0;
  HRESULT hr = g_exec(g_pio, "ioctl_pio_read", in, 1, out, 1, &ret);
  if (FAILED(hr)) {
    fprintf(stderr, "pio_read(0x%llx) failed: 0x%lx\n", port, hr);
    return -1;
  }
  *val = out[0];
  return 0;
}

static int PioWrite(ULONG64 port, ULONG64 val) {
  ULONG64 in[2] = {port, val}, out[1];
  SIZE_T ret = 0;
  HRESULT hr = g_exec(g_pio, "ioctl_pio_write", in, 2, out, 0, &ret);
  if (FAILED(hr)) {
    fprintf(stderr, "pio_write(0x%llx, 0x%llx) failed: 0x%lx\n", port, val, hr);
    return -1;
  }
  return 0;
}

// Wait for an EC status bit. bit: EC_SC_IBF waits-for-clear, EC_SC_OBF
// waits-for-set. Returns 0 on success, -1 on timeout.
static int WaitEc(int bit, int wantSet) {
  for (int i = 0; i < 2000; i++) {  // ~100 ms budget
    ULONG64 sc = 0;
    if (PioRead(EC_SC_PORT, &sc) != 0) return -1;
    if (!!(sc & bit) == !!wantSet) return 0;
    Sleep(0);
  }
  fprintf(stderr, "EC timeout waiting %s bit 0x%x\n", wantSet ? "set" : "clear",
          bit);
  return -1;
}

static int EcRead(ULONG64 addr, ULONG64* val) {
  // Drain a stale output byte left by an interrupted transaction.
  ULONG64 sc = 0;
  if (PioRead(EC_SC_PORT, &sc) == 0 && (sc & EC_SC_OBF)) {
    ULONG64 junk = 0;
    PioRead(EC_DATA_PORT, &junk);
  }
  for (int attempt = 0; attempt < 3; attempt++) {
    if (WaitEc(EC_SC_IBF, 0)) continue;
    if (PioWrite(EC_SC_PORT, EC_CMD_READ)) continue;
    if (WaitEc(EC_SC_IBF, 0)) continue;
    if (PioWrite(EC_DATA_PORT, addr)) continue;
    if (WaitEc(EC_SC_OBF, 1)) continue;
    if (PioRead(EC_DATA_PORT, val) == 0) return 0;
  }
  return -1;
}

static int EcWrite(ULONG64 addr, ULONG64 val) {
  ULONG64 sc = 0;
  if (PioRead(EC_SC_PORT, &sc) == 0 && (sc & EC_SC_OBF)) {
    ULONG64 junk = 0;
    PioRead(EC_DATA_PORT, &junk);
  }
  for (int attempt = 0; attempt < 3; attempt++) {
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

int main(int argc, char** argv) {
  HMODULE lib = LoadLibraryW(L"C:\\Program Files\\PawnIO\\PawnIOLib.dll");
  if (!lib) {
    fprintf(stderr, "PawnIOLib.dll not found: %lu\n", GetLastError());
    return 2;
  }
  auto p_open = (pawnio_open_fn)GetProcAddress(lib, "pawnio_open");
  auto p_load = (pawnio_load_fn)GetProcAddress(lib, "pawnio_load");
  g_exec = (pawnio_execute_fn)GetProcAddress(lib, "pawnio_execute");
  auto p_close = (pawnio_close_fn)GetProcAddress(lib, "pawnio_close");
  if (!p_open || !p_load || !g_exec || !p_close) {
    fprintf(stderr, "PawnIOLib exports missing\n");
    return 2;
  }

  HANDLE h = nullptr;
  HRESULT hr = p_open(&h);
  if (FAILED(hr) || !h) {
    fprintf(stderr, "pawnio_open failed: 0x%lx\n", hr);
    return 2;
  }
  g_pio = h;

  // Load the signed EC module blob.
  const wchar_t* blobPath = L"C:\\Users\\user\\Code\\netturbine\\windows\\"
                            L"tools\\pawnio_modules\\LpcACPIEC.bin";
  HANDLE f = CreateFileW(blobPath, GENERIC_READ, FILE_SHARE_READ, nullptr,
                         OPEN_EXISTING, 0, nullptr);
  if (f == INVALID_HANDLE_VALUE) {
    fprintf(stderr, "cannot open blob: %lu\n", GetLastError());
    return 2;
  }
  DWORD sz = GetFileSize(f, nullptr);
  std::vector<BYTE> blob(sz);
  DWORD rd = 0;
  ReadFile(f, blob.data(), sz, &rd, nullptr);
  CloseHandle(f);
  hr = p_load(h, blob.data(), blob.size());
  if (FAILED(hr)) {
    fprintf(stderr, "pawnio_load failed: 0x%lx\n", hr);
    return 2;
  }

  // Global mutex serializing EC access with acpi.sys's EC driver.
  HANDLE ecMutex = CreateMutexW(nullptr, FALSE, L"Global\\Access_EC");
  if (!ecMutex) {
    fprintf(stderr, "warning: Access_EC mutex failed (%lu); continuing "
                    "without serialization\n", GetLastError());
  } else if (GetLastError() == ERROR_ALREADY_EXISTS) {
    fprintf(stderr, "(Access_EC mutex existed — serializing with ec.sys)\n");
  }

  bool isWrite = argc >= 4 && strcmp(argv[1], "write") == 0;
  std::vector<ULONG64> addrs;
  ULONG64 wval = 0;
  if (isWrite) {
    addrs.push_back(strtoull(argv[2], nullptr, 0));
    wval = strtoull(argv[3], nullptr, 0);
  } else if (argc >= 3 && strcmp(argv[1], "read") == 0) {
    for (int i = 2; i < argc; i++) addrs.push_back(strtoull(argv[i], nullptr, 0));
  } else if (argc >= 3 && strcmp(argv[1], "dump") == 0 &&
             strcmp(argv[2], "all") == 0) {
    for (ULONG64 a = 0; a < 256; a++) addrs.push_back(a);
  } else {
    // dump: all candidate fan registers from the DSDT field map
    const ULONG64 all[] = {0x95, 0x83, 0x94, 0x82, 0x93, 0x81, 0x3D};
    addrs.assign(all, all + sizeof(all) / sizeof(all[0]));
  }

  if (ecMutex) WaitForSingleObject(ecMutex, 5000);
  int rc = 0;
  for (ULONG64 a : addrs) {
    if (isWrite) {
      if (EcWrite(a, wval) == 0)
        printf("EC[0x%02llX] <- 0x%02llX\n", a, wval);
      else
        rc = 3;
      continue;
    }
    ULONG64 v = 0;
    if (EcRead(a, &v) == 0)
      printf("EC[0x%02llX] = 0x%02llX (%llu)\n", a, v, v);
    else
      rc = 3;
  }
  if (ecMutex) {
    ReleaseMutex(ecMutex);
    CloseHandle(ecMutex);
  }
  p_close(h);
  return rc;
}
