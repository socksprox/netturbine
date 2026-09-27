#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

// HKCU\Software\Microsoft\Windows\CurrentVersion\Run — the per-user startup
// registry key. Toggling must never require admin, so HKCU only.
constexpr const wchar_t kRunKeyPath[] =
    L"Software\\Microsoft\\Windows\\CurrentVersion\\Run";
constexpr const wchar_t kRunValueName[] = L"netturbine";

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
      this->Show();
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
    ShowAndFocus();
    result->Success();
  } else if (name == "quitApp") {
    DestroyWindow(GetHandle());  // -> WM_DESTROY -> PostQuitMessage
    result->Success();
  } else {
    result->NotImplemented();
  }
}

// Fan backend contract for lib/api/windows/windows_fan_controller.dart.
// TODO(fan-backend): hardware access is driver/EC/vendor-specific — pick a
// mechanism (e.g. WMI CIM, a kernel driver, or a vendor SDK) and fill this in.
// Until then the app reports zero controllable fans and degrades gracefully.
void FlutterWindow::HandleFanCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& name = call.method_name();
  if (name == "getFans") {
    flutter::EncodableMap capabilities{
        {flutter::EncodableValue("canReadRpm"), flutter::EncodableValue(false)},
        {flutter::EncodableValue("canSetSpeed"),
         flutter::EncodableValue(false)},
    };
    flutter::EncodableMap payload{
        {flutter::EncodableValue("capabilities"),
         flutter::EncodableValue(capabilities)},
        {flutter::EncodableValue("fans"), flutter::EncodableValue(
                                             flutter::EncodableList{})},
    };
    result->Success(flutter::EncodableValue(payload));
  } else if (name == "setSpeed" || name == "resetToAuto") {
    result->Error("unsupported", "No fan backend is available yet.");
  } else {
    result->NotImplemented();
  }
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
