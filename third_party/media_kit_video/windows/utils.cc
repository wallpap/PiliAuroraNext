// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#include "utils.h"

#include <optional>

typedef LONG NTSTATUS, *PNTSTATUS;
#define STATUS_SUCCESS (0x00000000)

typedef NTSTATUS(WINAPI* RtlGetVersionPtr)(PRTL_OSVERSIONINFOW);

namespace {

struct WindowFrame {
  LONG_PTR style = 0;
  RECT bounds{};
};

bool fullscreen_confirmed = false;
std::optional<WindowFrame> windowed_frame;

bool ReadWindowFrame(HWND window, WindowFrame& frame) {
  ::SetLastError(ERROR_SUCCESS);
  frame.style = ::GetWindowLongPtr(window, GWL_STYLE);
  return (frame.style != 0 || ::GetLastError() == ERROR_SUCCESS) &&
         ::GetWindowRect(window, &frame.bounds);
}

bool ApplyWindowFrame(HWND window, const WindowFrame& frame) {
  ::SetLastError(ERROR_SUCCESS);
  if (!::SetWindowLongPtr(window, GWL_STYLE, frame.style) &&
      ::GetLastError() != ERROR_SUCCESS) {
    return false;
  }
  const auto& bounds = frame.bounds;
  if (!::SetWindowPos(window, nullptr, bounds.left, bounds.top,
                      bounds.right - bounds.left, bounds.bottom - bounds.top,
                      SWP_NOACTIVATE | SWP_NOZORDER | SWP_FRAMECHANGED)) {
    return false;
  }
  WindowFrame actual;
  return ReadWindowFrame(window, actual) &&
         (actual.style & WS_OVERLAPPEDWINDOW) ==
             (frame.style & WS_OVERLAPPEDWINDOW) &&
         ::EqualRect(&actual.bounds, &bounds);
}

}

bool Utils::EnterNativeFullscreen(HWND window) {
  if (fullscreen_confirmed) return ::IsWindow(window);

  WindowFrame previous;
  MONITORINFO monitor{};
  monitor.cbSize = sizeof(monitor);
  if (!ReadWindowFrame(window, previous) ||
      !::GetMonitorInfo(::MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                        &monitor)) {
    return false;
  }
  if (!windowed_frame) windowed_frame = previous;
  const WindowFrame fullscreen{previous.style & ~WS_OVERLAPPEDWINDOW,
                               monitor.rcMonitor};
  if (!ApplyWindowFrame(window, fullscreen)) {
    if (ApplyWindowFrame(window, *windowed_frame)) windowed_frame.reset();
    return false;
  }
  fullscreen_confirmed = true;
  return true;
}

bool Utils::ExitNativeFullscreen(HWND window) {
  if (!windowed_frame) return ::IsWindow(window);

  WindowFrame previous;
  if (!ReadWindowFrame(window, previous)) return false;
  const WindowFrame restored{
      (previous.style & ~WS_OVERLAPPEDWINDOW) |
          (windowed_frame->style & WS_OVERLAPPEDWINDOW),
      windowed_frame->bounds};
  if (!ApplyWindowFrame(window, restored)) {
    ApplyWindowFrame(window, previous);
    return false;
  }
  windowed_frame.reset();
  fullscreen_confirmed = false;
  return true;
}

RTL_OSVERSIONINFOW Utils::GetWindowsVersion() {
  HMODULE handle = ::LoadLibraryW(L"ntdll.dll");
  RTL_OSVERSIONINFOW rtl_os_version_info = {0};
  rtl_os_version_info.dwBuildNumber = 0;
  rtl_os_version_info.dwOSVersionInfoSize = sizeof(rtl_os_version_info);
  if (handle) {
    RtlGetVersionPtr rtl_get_version_ptr = reinterpret_cast<RtlGetVersionPtr>(
        ::GetProcAddress(handle, "RtlGetVersion"));
    if (rtl_get_version_ptr != nullptr) {
      rtl_get_version_ptr(&rtl_os_version_info);
    }
    ::FreeLibrary(handle);
  }
  return rtl_os_version_info;
}

bool Utils::IsWindows10RTMOrGreater() {
  return GetWindowsVersion().dwBuildNumber >= 10240;
}
