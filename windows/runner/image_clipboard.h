#ifndef RUNNER_IMAGE_CLIPBOARD_H_
#define RUNNER_IMAGE_CLIPBOARD_H_

#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>

std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
RegisterImageClipboard(flutter::BinaryMessenger* messenger, HWND window);

#endif  // RUNNER_IMAGE_CLIPBOARD_H_
