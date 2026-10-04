#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>

// Window class name — also used by main.cpp for single-instance detection.
constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// WM_APP messages used by the tray icon and the single-instance handshake.
constexpr UINT kTrayCallbackMessage = WM_APP + 1;  // Shell_NotifyIcon callback
constexpr UINT kShowWindowMessage = WM_APP + 2;    // "show" from 2nd instance

// A class abstraction for a high DPI-aware Win32 Window. Intended to be
// inherited from by classes that wish to specialize with custom
// rendering and input handling
class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  // Creates a win32 window with |title| that is positioned and sized using
  // |origin| and |size|. New windows are created on the default monitor. Window
  // sizes are specified to the OS in physical pixels, hence to ensure a
  // consistent size this function will scale the inputted width and height as
  // as appropriate for the default monitor. The window is invisible until
  // |Show| is called. Returns true if the window was created successfully.
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  // Shows the borderless flyout window directly above the tray icon (anchored
  // to the taskbar edge) and brings it to the foreground.
  void ShowAboveTray();

  // Hides the window without closing it (tray behavior).
  void Hide();

  // When pinned, the flyout stays visible (and on top) after losing
  // activation instead of auto-hiding.
  void SetPinned(bool pinned);

  // Release OS resources associated with window.
  void Destroy();

  // Inserts |content| into the window tree.
  void SetChildContent(HWND content);

  // Returns the backing Window handle to enable clients to set icon and other
  // window properties. Returns nullptr if the window has been destroyed.
  HWND GetHandle();

  // If true, closing this window will quit the application.
  void SetQuitOnClose(bool quit_on_close);

  // Return a RECT representing the bounds of the current client area.
  RECT GetClientArea();

 protected:
  // Processes and route salient window messages for mouse handling,
  // size change and DPI. Delegates handling of these to member overloads that
  // inheriting classes can handle.
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  // Called when CreateAndShow is called, allowing subclass window-related
  // setup. Subclasses should return false if setup fails.
  virtual bool OnCreate();

  // Called when Destroy is called.
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  // OS callback called by message pump. Handles the WM_NCCREATE message which
  // is passed when the non-client area is being created and enables automatic
  // non-client DPI scaling so that the non-client area automatically
  // responds to changes in DPI. All other messages are handled by
  // MessageHandler.
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  // Retrieves a class instance pointer for |window|
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  // Update the window frame's theme to match the system theme.
  static void UpdateTheme(HWND const window);

  // Adds/removes the notification-area (tray) icon for this window.
  void SetupTrayIcon();
  void RemoveTrayIcon();

  bool quit_on_close_ = false;

  // Pinned flyouts ignore the blur-driven Hide() in WM_ACTIVATE.
  bool pinned_ = false;

  // GetTickCount64() of the last blur-driven Hide(). The tray click that
  // causes the blur would otherwise reopen the flyout a moment later.
  ULONGLONG last_blur_hide_tick_ = 0;

  // Flyout slide animation state (driven by a WM_TIMER on the window).
  ULONGLONG flyout_anim_start_ = 0;
  int flyout_anim_from_x_ = 0;
  int flyout_anim_from_y_ = 0;
  int flyout_anim_target_x_ = 0;
  int flyout_anim_target_y_ = 0;

  // Offset toward the taskbar edge, remembered from the last show so dismiss
  // slides back the same way even if the cursor has since moved elsewhere.
  int flyout_dismiss_dx_ = 0;
  int flyout_dismiss_dy_ = 0;

  // True while the slide-out runs; the final timer tick calls SW_HIDE.
  bool flyout_hiding_ = false;

  // window handle for top level window.
  HWND window_handle_ = nullptr;

  // window handle for hosted content.
  HWND child_content_ = nullptr;
};

#endif  // RUNNER_WIN32_WINDOW_H_
