#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32_window.h"
#include "gpu_metrics.h"
#include "memory_metrics_channel.h"

class FlutterWindow : public Win32Window {
 public:
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  flutter::DartProject project_;
  std::unique_ptr<GpuMetrics> gpu_metrics_;
  std::unique_ptr<MemoryMetricsChannel> memory_metrics_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> background_channel_;

  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
};

#endif
