#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Single instance: if another copy is running, ask it to show its window
  // and exit. Skipped in debug builds — `flutter run` needs the child process
  // to stay alive or the launch fails, and running multiple dev copies is
  // often useful.
  HANDLE mutex = nullptr;
#ifndef _DEBUG
  mutex = CreateMutexW(nullptr, TRUE, L"Local\\netturbine-single-instance");
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    if (HWND existing = FindWindowW(kWindowClassName, nullptr)) {
      PostMessageW(existing, kShowWindowMessage, 0, 0);
    }
    CloseHandle(mutex);
    ::CoUninitialize();
    return EXIT_SUCCESS;
  }
#endif

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
  // Debug builds always show the window — `flutter run` passes no --show and
  // a hidden window looks like a failed launch.
#ifdef _DEBUG
  const bool start_visible = true;
#else
  const bool start_visible =
      std::find(command_line_arguments.begin(), command_line_arguments.end(),
                "--show") != command_line_arguments.end();
#endif

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project, start_visible);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(380, 500);
  if (!window.Create(L"netturbine", origin, size)) {
    CloseHandle(mutex);
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  CloseHandle(mutex);
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
