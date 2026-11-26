import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


CPP = r"""
#include <windows.h>

#include <iostream>

enum class PositionFault { none, failure, unchanged };
static PositionFault next_fault = PositionFault::none;

static BOOL ProbeSetWindowPos(HWND window, HWND insert_after, int left, int top,
                              int width, int height, UINT flags) {
  const auto fault = next_fault;
  next_fault = PositionFault::none;
  if (fault == PositionFault::failure) {
    SetLastError(ERROR_ACCESS_DENIED);
    return FALSE;
  }
  if (fault == PositionFault::unchanged) return TRUE;
  return SetWindowPos(window, insert_after, left, top, width, height, flags);
}

#define SetWindowPos ProbeSetWindowPos
#include "utils.cc"
#undef SetWindowPos

bool AtBounds(HWND window, const RECT& target) {
  RECT bounds{};
  return GetWindowRect(window, &bounds) && EqualRect(&bounds, &target);
}

bool Check(bool expected, const char* message) {
  if (!expected) std::cerr << message << '\n';
  return expected;
}

int main() {
  const auto window = CreateWindowExW(
      0, L"STATIC", L"Playback fullscreen probe", WS_OVERLAPPEDWINDOW, 50, 50,
      320, 240, nullptr, nullptr, GetModuleHandleW(nullptr), nullptr);
  RECT initial{};
  MONITORINFO monitor = {sizeof(MONITORINFO)};
  if (!window || !GetWindowRect(window, &initial) ||
      !GetMonitorInfoW(MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST),
                       &monitor)) {
    return 2;
  }

  const auto enter = [&] { return Utils::EnterNativeFullscreen(window); };
  const auto exit = [&] { return Utils::ExitNativeFullscreen(window); };
  const auto windowed = [&] {
    return AtBounds(window, initial) &&
           (GetWindowLongPtr(window, GWL_STYLE) & WS_OVERLAPPEDWINDOW) ==
               WS_OVERLAPPEDWINDOW;
  };
  const auto fullscreen = [&] {
    return AtBounds(window, monitor.rcMonitor) &&
           !(GetWindowLongPtr(window, GWL_STYLE) & WS_OVERLAPPEDWINDOW);
  };

  next_fault = PositionFault::failure;
  bool passed = Check(!enter() && windowed(),
                      "failed enter must be rejected and rolled back");
  next_fault = PositionFault::unchanged;
  passed &= Check(!enter() && windowed(), "enter must verify monitor bounds");
  passed &= Check(enter() && fullscreen(), "enter must retry after failure");
  next_fault = PositionFault::failure;
  passed &= Check(!exit() && fullscreen(),
                  "failed exit must be rejected and rolled back");
  passed &= Check(exit() && windowed(), "exit must retry after failure");
  passed &= Check(exit() && windowed(), "confirmed exit must be idempotent");
  DestroyWindow(window);

  const auto maximized = CreateWindowExW(
      0, L"STATIC", L"Maximized playback probe",
      WS_OVERLAPPEDWINDOW | WS_MAXIMIZE, 50, 50, 320, 240, nullptr, nullptr,
      GetModuleHandleW(nullptr), nullptr);
  RECT maximized_bounds{};
  passed &= Check(maximized && IsZoomed(maximized) &&
                      GetWindowRect(maximized, &maximized_bounds),
                  "maximized window setup must be valid");
  if (maximized) {
    passed &= Check(Utils::EnterNativeFullscreen(maximized) &&
                        AtBounds(maximized, monitor.rcMonitor),
                    "maximized window must enter fullscreen");
    passed &= Check(Utils::ExitNativeFullscreen(maximized) &&
                        IsZoomed(maximized) && AtBounds(maximized, maximized_bounds),
                    "maximized window must recover its state and bounds");
    DestroyWindow(maximized);
  }
  return passed ? 0 : 1;
}
"""


@unittest.skipUnless(os.name == "nt" and shutil.which("g++"), "requires Windows and g++")
class WindowsNativeFullscreenTest(unittest.TestCase):
    def test_native_transition_receipt_and_retry(self):
        root = Path(__file__).resolve().parents[3]
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "fullscreen_probe.cpp"
            binary = Path(directory) / "fullscreen_probe.exe"
            source.write_text(CPP, encoding="utf-8")
            subprocess.run(
                [
                    "g++", "-std=c++17", "-DUNICODE", "-D_UNICODE",
                    "-static-libgcc", "-static-libstdc++", "-I",
                    str(root / "third_party/media_kit_video/windows"),
                    str(source), "-o", str(binary), "-luser32",
                ],
                check=True,
            )
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
