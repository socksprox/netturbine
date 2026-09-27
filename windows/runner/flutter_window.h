#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  // |start_visible| controls whether the window shows on launch — a tray app
  // normally starts hidden unless launched with --show.
  FlutterWindow(const flutter::DartProject& project, bool start_visible);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // MethodChannel handlers — see lib/api/windows/ for the Dart side.
  void HandleSystemCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void HandleFanCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // The project to run.
  flutter::DartProject project_;

  // Whether to show the window once the first frame renders.
  bool start_visible_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // "netturbine/system": startup registry key, window show/quit.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_channel_;
  // "netturbine/fan": fan backend (stub until a hardware mechanism is chosen).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> fan_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
