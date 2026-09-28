#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// HKCU\Software\Microsoft\Windows\CurrentVersion\Run — the per-user startup
// registry key. Toggling must never require admin, so HKCU only.
constexpr const wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kRunValueName[] = L"netturbine";

// Sends one line to the elevated fan helper over \\.\pipe\netturbine_fan and
// reads back one reply line. Returns false when the helper is unreachable.
// Protocol (see windows/tools/fan_helper.cpp):
//   "list"      -> "ok <count>"
//   "read <i>"  -> "ok <percent 0-100>"
//   "mode <i>"  -> "ok <0 auto | 1 manual>"
//   "set <i> <percent>" / "auto <i>" -> "ok" | "err <msg>"
bool PipeRequest(const std::string& cmd, std::string* reply) {
  HANDLE pipe = CreateFileW(L"\\\\.\\pipe\\netturbine_fan",
                            GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                            OPEN_EXISTING, 0, nullptr);
  if (pipe == INVALID_HANDLE_VALUE) {
    if (GetLastError() != ERROR_PIPE_BUSY ||
        !WaitNamedPipeW(L"\\\\.\\pipe\\netturbine_fan", 3000)) {
      return false;
    }
    pipe = CreateFileW(L"\\\\.\\pipe\\netturbine_fan",
                       GENERIC_READ | GENERIC_WRITE, 0, nullptr,
                       OPEN_EXISTING, 0, nullptr);
    if (pipe == INVALID_HANDLE_VALUE) {
      return false;
    }
  }
  std::string line = cmd + "\n";
  DWORD n = 0;
  bool ok = WriteFile(pipe, line.c_str(), static_cast<DWORD>(line.size()), &n,
                      nullptr);
  char buf[256];
  if (ok) {
    ok = ReadFile(pipe, buf, sizeof(buf) - 1, &n, nullptr) && n > 0;
  }
  CloseHandle(pipe);
  if (!ok) {
    return false;
  }
  buf[n] = 0;
  *reply = buf;
  while (!reply->empty() &&
         (reply->back() == '\n' || reply->back() == '\r')) {
    reply->pop_back();
  }
  return true;
}

// Checks a reply is "ok ..." and optionally parses the trailing integer.
bool PipeOk(const std::string& reply, int* value = nullptr) {
  if (reply.rfind("ok", 0) != 0) {
    return false;
  }
  if (value != nullptr) {
    if (sscanf_s(reply.c_str(), "ok %d", value) != 1) {
      return false;
    }
  }
  return true;
}

// "fan0" -> 0, "fan1" -> 1; anything else -> -1.
int ParseFanId(const flutter::EncodableValue& arg) {
  const auto* s = std::get_if<std::string>(&arg);
  if (s == nullptr || s->rfind("fan", 0) != 0) {
    return -1;
  }
  return atoi(s->c_str() + 3);
}

bool IsLaunchAtStartupEnabled() {
  HKEY key;
  if (RegOpenKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, KEY_READ, &key) !=
      ERROR_SUCCESS) {
    return false;
  }
  DWORD type = 0;
  bool enabled = RegQueryValueExW(key, kRunValueName, nullptr, &type, nullptr,
                                  nullptr) == ERROR_SUCCESS;
  RegCloseKey(key);
  return enabled;
}

// Writes (or deletes) "netturbine"="<exe path>" under the Run key.
bool SetLaunchAtStartup(bool enabled) {
  HKEY key;
  if (RegCreateKeyExW(HKEY_CURRENT_USER, kRunKeyPath, 0, nullptr, 0,
                      KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
    return false;
  }
  LSTATUS status;
  if (enabled) {
    wchar_t path[MAX_PATH];
    DWORD length = GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring value = L"\"" + std::wstring(path, length) + L"\"";
    status = RegSetValueExW(
        key, kRunValueName, 0, REG_SZ,
        reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  } else {
    status = RegDeleteValueW(key, kRunValueName);
    if (status == ERROR_FILE_NOT_FOUND) {
      status = ERROR_SUCCESS;
    }
  }
  RegCloseKey(key);
  return status == ERROR_SUCCESS;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             bool start_visible)
    : project_(project), start_visible_(start_visible) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  auto* messenger = flutter_controller_->engine()->messenger();
  const auto* codec = &flutter::StandardMethodCodec::GetInstance();

  system_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "netturbine/system", codec);
  system_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleSystemCall(call, std::move(result)); });

  fan_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, "netturbine/fan", codec);
  fan_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) { HandleFanCall(call, std::move(result)); });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    if (start_visible_) {
      this->ShowAboveTray();
    }
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleSystemCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& name = call.method_name();
  if (name == "getLaunchAtStartup") {
    result->Success(flutter::EncodableValue(IsLaunchAtStartupEnabled()));
  } else if (name == "setLaunchAtStartup") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    bool enabled = false;
    if (args != nullptr) {
      auto it = args->find(flutter::EncodableValue("enabled"));
      if (it != args->end()) {
        enabled = std::get<bool>(it->second);
      }
    }
    result->Success(flutter::EncodableValue(SetLaunchAtStartup(enabled)));
  } else if (name == "showWindow") {
    ShowAboveTray();
    result->Success();
  } else if (name == "quitApp") {
    DestroyWindow(GetHandle());  // -> WM_DESTROY -> PostQuitMessage
    result->Success();
  } else {
    result->NotImplemented();
  }
}

// Fan backend contract for lib/api/windows/windows_fan_controller.dart.
// Proxies to the elevated NetturbineFanHelper service via
// \\.\pipe\netturbine_fan (PawnIO + EC registers, see windows/tools/).
// When the helper is not installed/running, reports zero fans so the UI
// degrades gracefully.
void FlutterWindow::HandleFanCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& name = call.method_name();
  if (name == "getFans") {
    std::string reply;
    int count = 0;
    bool up = PipeRequest("list", &reply) && PipeOk(reply, &count);
    flutter::EncodableMap capabilities{
        {flutter::EncodableValue("canReadRpm"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("canSetSpeed"), flutter::EncodableValue(up)},
    };
    flutter::EncodableList fans;
    for (int i = 0; i < (up ? count : 0); i++) {
      int percent = 0;
      bool readable =
          PipeRequest("read " + std::to_string(i), &reply) &&
          PipeOk(reply, &percent);
      int manual = 0;
      PipeRequest("mode " + std::to_string(i), &reply);
      PipeOk(reply, &manual);
      flutter::EncodableMap fan{
          {flutter::EncodableValue("id"),
           flutter::EncodableValue("fan" + std::to_string(i))},
          {flutter::EncodableValue("label"),
           flutter::EncodableValue("Fan " + std::to_string(i + 1))},
          {flutter::EncodableValue("speedPercent"),
           readable ? flutter::EncodableValue(percent)
                    : flutter::EncodableValue()},
          {flutter::EncodableValue("canControl"),
           flutter::EncodableValue(true)},
          {flutter::EncodableValue("isAuto"),
           flutter::EncodableValue(manual == 0)},
      };
      fans.push_back(flutter::EncodableValue(fan));
    }
    flutter::EncodableList temps;
    if (up && PipeRequest("temps", &reply) &&
        reply.rfind("ok", 0) == 0) {
      // "ok <label>=<celsius> [<label>=<celsius> ...]" — '_' in labels is a
      // space placeholder.
      size_t pos = 2;
      while (pos < reply.size()) {
        while (pos < reply.size() && reply[pos] == ' ') pos++;
        size_t end = reply.find(' ', pos);
        if (end == std::string::npos) end = reply.size();
        std::string tok = reply.substr(pos, end - pos);
        pos = end;
        auto eq = tok.find('=');
        if (eq == std::string::npos || eq == 0) continue;
        std::string label = tok.substr(0, eq);
        std::replace(label.begin(), label.end(), '_', ' ');
        int celsius = atoi(tok.c_str() + eq + 1);
        std::string id = tok.substr(0, eq);
        std::transform(id.begin(), id.end(), id.begin(),
                       [](unsigned char c) { return (char)tolower(c); });
        flutter::EncodableMap sensor{
            {flutter::EncodableValue("id"), flutter::EncodableValue(id)},
            {flutter::EncodableValue("label"),
             flutter::EncodableValue(label)},
            {flutter::EncodableValue("celsius"),
             flutter::EncodableValue(celsius)},
        };
        temps.push_back(flutter::EncodableValue(sensor));
      }
    }
    flutter::EncodableMap payload{
        {flutter::EncodableValue("capabilities"),
         flutter::EncodableValue(capabilities)},
        {flutter::EncodableValue("fans"), flutter::EncodableValue(fans)},
        {flutter::EncodableValue("temps"), flutter::EncodableValue(temps)},
    };
    result->Success(flutter::EncodableValue(payload));
    return;
  }
  if (name == "setSpeed" || name == "resetToAuto") {
    const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
    if (args == nullptr) {
      result->Error("bad_args", "Expected a map of arguments.");
      return;
    }
    auto it = args->find(flutter::EncodableValue("fanId"));
    int fan = it == args->end() ? -1 : ParseFanId(it->second);
    std::string cmd;
    if (name == "setSpeed") {
      auto pi = args->find(flutter::EncodableValue("percent"));
      int pct = pi == args->end() ? -1 : std::get<int>(pi->second);
      if (fan < 0 || pct < 0 || pct > 100) {
        result->Error("bad_args", "fanId or percent invalid.");
        return;
      }
      cmd = "set " + std::to_string(fan) + " " + std::to_string(pct);
    } else {
      if (fan < 0) {
        result->Error("bad_args", "fanId invalid.");
        return;
      }
      cmd = "auto " + std::to_string(fan);
    }
    std::string reply;
    if (!PipeRequest(cmd, &reply)) {
      result->Error("unavailable", "Fan helper service is not running.");
      return;
    }
    if (!PipeOk(reply)) {
      result->Error("ec_error", reply);
      return;
    }
    result->Success();
    return;
  }
  result->NotImplemented();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
