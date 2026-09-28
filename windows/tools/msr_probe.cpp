// msr_probe — print CPU package temperature via PawnIO IntelMSR module.
#include <windows.h>
#include <cstdio>
#include <string>
#include <vector>

typedef HRESULT(STDAPICALLTYPE* pio_open_fn)(PHANDLE);
typedef HRESULT(STDAPICALLTYPE* pio_load_fn)(HANDLE, const UCHAR*, SIZE_T);
typedef HRESULT(STDAPICALLTYPE* pio_exec_fn)(HANDLE, PCSTR, const ULONG64*,
                                           SIZE_T, PULONG64, SIZE_T, PSIZE_T);
typedef HRESULT(STDAPICALLTYPE* pio_close_fn)(HANDLE);

static pio_exec_fn exec_;
static HANDLE pio_;

static int ReadMsr(ULONG64 msr, ULONG64* v) {
  ULONG64 in[1] = {msr}, out[1] = {0};
  SIZE_T ret = 0;
  if (FAILED(exec_(pio_, "ioctl_read_msr", in, 1, out, 1, &ret))) return -1;
  *v = out[0];
  return 0;
}

int main() {
  HMODULE lib = LoadLibraryW(L"C:\\Program Files\\PawnIO\\PawnIOLib.dll");
  if (!lib) { fprintf(stderr, "no PawnIOLib\n"); return 2; }
  auto open = (pio_open_fn)GetProcAddress(lib, "pawnio_open");
  auto load = (pio_load_fn)GetProcAddress(lib, "pawnio_load");
  exec_ = (pio_exec_fn)GetProcAddress(lib, "pawnio_execute");
  auto close = (pio_close_fn)GetProcAddress(lib, "pawnio_close");
  if (FAILED(open(&pio_)) || !pio_) { fprintf(stderr, "open failed\n"); return 2; }

  wchar_t dir[MAX_PATH];
  GetModuleFileNameW(nullptr, dir, MAX_PATH);
  wchar_t* slash = wcsrchr(dir, L'\\');
  if (slash) *slash = 0;
  std::wstring bp = std::wstring(dir) + L"\\IntelMSR.bin";
  HANDLE f = CreateFileW(bp.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                         OPEN_EXISTING, 0, nullptr);
  if (f == INVALID_HANDLE_VALUE) {
    bp = std::wstring(dir) + L"\\pawnio_modules\\IntelMSR.bin";
    f = CreateFileW(bp.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                    OPEN_EXISTING, 0, nullptr);
  }
  if (f == INVALID_HANDLE_VALUE) { fprintf(stderr, "no blob\n"); return 2; }
  DWORD sz = GetFileSize(f, nullptr);
  std::vector<BYTE> blob(sz);
  DWORD rd;
  ReadFile(f, blob.data(), sz, &rd, nullptr);
  CloseHandle(f);
  if (FAILED(load(pio_, blob.data(), blob.size()))) {
    fprintf(stderr, "load failed\n");
    return 2;
  }

  ULONG64 tjf = 0, s = 0;
  if (ReadMsr(0x1A2, &tjf) || ReadMsr(0x1B1, &s)) {
    fprintf(stderr, "msr read failed\n");
    return 2;
  }
  int tj = (int)((tjf >> 16) & 0xFF);
  int temp = (s & (1ULL << 31)) ? tj - (int)((s >> 16) & 0x7F) : -1;
  printf("tjmax=%d cpu_pkg=%d\n", tj, temp);
  close(pio_);
  return 0;
}
