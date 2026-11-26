// This file is a part of media_kit
// (https://github.com/media-kit/media-kit).
//
// Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
// All rights reserved.
// Use of this source code is governed by MIT license that can be found in the
// LICENSE file.

#ifndef UTILS_H_
#define UTILS_H_

#include <cstdint>

#include <Windows.h>

class Utils {
 public:
  static bool EnterNativeFullscreen(HWND window);

  static bool ExitNativeFullscreen(HWND window);

  static RTL_OSVERSIONINFOW GetWindowsVersion();

  static bool IsWindows10RTMOrGreater();
};

#endif  // UTILS_H_
