// acpi_probe — evaluate ACPI control methods via IOCTL_ACPI_EVAL_METHOD_EX.
// Usage (requires elevation):
//   acpi_probe.exe read  <method-path> <offset>        — 1 int arg, print result
//   acpi_probe.exe read0 <method-path>                 — no args
//   acpi_probe.exe write <method-path> <off> <val>     — 2 int args
//   acpi_probe.exe mdec  <method-path> <off> <and> <or>— 3 int args
//
// Offsets/values may be decimal or 0x-prefixed hex.
// Method path e.g. \_SB.PC00.LPCB.EC0_.RDEC — resolved by acpi.sys.

#include <windows.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

// From WDK acpiioct.h (not shipped in the user-mode SDK).
#define FILE_DEVICE_ACPI 0x00000032
#define IOCTL_ACPI_EVAL_METHOD_V1 \
    CTL_CODE(FILE_DEVICE_ACPI, 1, METHOD_BUFFERED, \
             FILE_READ_ACCESS | FILE_WRITE_ACCESS)
#define IOCTL_ACPI_EVAL_METHOD_EX \
    CTL_CODE(FILE_DEVICE_ACPI, 6, METHOD_BUFFERED, \
             FILE_READ_ACCESS | FILE_WRITE_ACCESS)

#define ACPI_EVAL_INPUT_BUFFER_COMPLEX_SIGNATURE_V1 'CieA'
#define ACPI_EVAL_INPUT_BUFFER_COMPLEX_SIGNATURE_V1_EX 'FieA'
#define ACPI_EVAL_OUTPUT_BUFFER_SIGNATURE_V1 'BoeA'
#define ACPI_METHOD_ARGUMENT_INTEGER 0x0

#pragma pack(push, 1)
struct ACPI_METHOD_ARGUMENT_V1 {
  USHORT Type;
  USHORT DataLength;
  ULONG Argument;
};

struct ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX {
  ULONG Signature;
  CHAR MethodName[256];
  ULONG Size;
  ULONG ArgumentCount;
  // ACPI_METHOD_ARGUMENT_V1 Argument[];
};

struct ACPI_EVAL_OUTPUT_BUFFER {
  ULONG Signature;
  ULONG Length;
  ULONG Count;
  // ACPI_METHOD_ARGUMENT_V1 Argument[];
};
#pragma pack(pop)

static ULONG ParseNumber(const char* s) {
  return static_cast<ULONG>(strtoul(s, nullptr, 0));
}

static int EvalMethod(HANDLE acpi, const char* path,
                      const std::vector<ULONG>& args, ULONG64* out) {
  // Input: header + ArgumentCount * sizeof(ACPI_METHOD_ARGUMENT_V1)
  const size_t inSize =
      sizeof(ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX) +
      args.size() * sizeof(ACPI_METHOD_ARGUMENT_V1);
  std::vector<BYTE> in(inSize, 0);
  auto* hdr = reinterpret_cast<ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX*>(in.data());
  hdr->Signature = ACPI_EVAL_INPUT_BUFFER_COMPLEX_SIGNATURE_V1_EX;
  strncpy_s(hdr->MethodName, path, sizeof(hdr->MethodName) - 1);
  hdr->ArgumentCount = static_cast<ULONG>(args.size());
  hdr->Size = static_cast<ULONG>(args.size() * sizeof(ACPI_METHOD_ARGUMENT_V1));

  auto* arg = reinterpret_cast<ACPI_METHOD_ARGUMENT_V1*>(in.data() +
      sizeof(ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX));
  for (size_t i = 0; i < args.size(); i++) {
    arg[i].Type = ACPI_METHOD_ARGUMENT_INTEGER;
    arg[i].DataLength = sizeof(ULONG);
    arg[i].Argument = args[i];
  }

  std::vector<BYTE> outBuf(4096, 0);
  DWORD returned = 0;
  BOOL ok = DeviceIoControl(acpi, IOCTL_ACPI_EVAL_METHOD_EX, in.data(),
                            static_cast<DWORD>(in.size()), outBuf.data(),
                            static_cast<DWORD>(outBuf.size()), &returned,
                            nullptr);
  DWORD err = ok ? 0 : GetLastError();
  if (!ok && err == ERROR_NOT_SUPPORTED) {
    // Fallback: V1 complex buffer — MethodName is a bare 4-char name
    // (last segment of the path). Immediate child of device only.
    const char* seg = strrchr(path, '.');
    seg = seg ? seg + 1 : (path[0] == '\\' ? path + 1 : path);
    CHAR name4[4] = {'_', '_', '_', '_'};
    memcpy(name4, seg, min(4, strlen(seg)));
    fprintf(stderr, "(EX unsupported, retrying V1 name=%.4s)\n", name4);

    struct V1Hdr {
      ULONG Signature;
      UCHAR MethodName[4];
      ULONG Size;
      ULONG ArgumentCount;
    };
    const size_t v1Size = sizeof(V1Hdr) + hdr->Size;
    std::vector<BYTE> v1(v1Size, 0);
    auto* v1h = reinterpret_cast<V1Hdr*>(v1.data());
    v1h->Signature = ACPI_EVAL_INPUT_BUFFER_COMPLEX_SIGNATURE_V1;
    memcpy(v1h->MethodName, name4, 4);
    v1h->Size = hdr->Size;
    v1h->ArgumentCount = hdr->ArgumentCount;
    memcpy(v1.data() + sizeof(V1Hdr),
           in.data() + sizeof(ACPI_EVAL_INPUT_BUFFER_COMPLEX_EX),
           hdr->Size);
    returned = 0;
    ok = DeviceIoControl(acpi, IOCTL_ACPI_EVAL_METHOD_V1, v1.data(),
                         static_cast<DWORD>(v1.size()), outBuf.data(),
                         static_cast<DWORD>(outBuf.size()), &returned,
                         nullptr);
    err = ok ? 0 : GetLastError();
  }
  if (!ok) {
    fprintf(stderr, "DeviceIoControl failed: %lu\n", err);
    return 2;
  }

  auto* outHdr = reinterpret_cast<ACPI_EVAL_OUTPUT_BUFFER*>(outBuf.data());
  if (outHdr->Signature != ACPI_EVAL_OUTPUT_BUFFER_SIGNATURE_V1 ||
      outHdr->Count == 0) {
    *out = 0;
    return 0;  // method returned void
  }
  auto* outArg = reinterpret_cast<ACPI_METHOD_ARGUMENT_V1*>(
      outBuf.data() + sizeof(ACPI_EVAL_OUTPUT_BUFFER));
  if (outArg->Type == ACPI_METHOD_ARGUMENT_INTEGER) {
    *out = outArg->Argument;
  } else {
    fprintf(stderr, "(non-integer result, type=%u len=%u)\n", outArg->Type,
            outArg->DataLength);
  }
  return 0;
}

int main(int argc, char** argv) {
  if (argc < 3) {
    fprintf(stderr,
            "usage:\n  acpi_probe read <path> <off>\n  acpi_probe read0 "
            "<path>\n  acpi_probe write <path> <off> <val>\n  acpi_probe mdec "
            "<path> <off> <and> <or>\n");
    return 1;
  }

  // FAN0 device interface (ACPI\PNP0C0B\0) registered by acpi.sys under
  // GUID {dbe4373d-3c81-40cb-ace4-e0e5d05f0c9f}. Overridable via ACPI_DEV env.
  const wchar_t* devPath =
      L"\\\\?\\ACPI#PNP0C0B#0#{dbe4373d-3c81-40cb-ace4-e0e5d05f0c9f}";
  if (const char* env = getenv("ACPI_DEV")) {
    wchar_t buf[256];
    mbstowcs_s(nullptr, buf, env, _countof(buf));
    devPath = buf;
  }
  HANDLE acpi = CreateFileW(devPath, GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (acpi == INVALID_HANDLE_VALUE) {
    fwprintf(stderr, L"cannot open %ls: %lu (need admin?)\n", devPath,
             GetLastError());
    return 2;
  }

  const char* cmd = argv[1];
  const char* path = argv[2];
  std::vector<ULONG> args;
  for (int i = 3; i < argc; i++) args.push_back(ParseNumber(argv[i]));

  ULONG64 result = 0;
  int rc = EvalMethod(acpi, path, args, &result);
  if (rc == 0) {
    printf("%s -> %llu (0x%llX)\n", path, result, result);
  }
  CloseHandle(acpi);
  return rc;
}
