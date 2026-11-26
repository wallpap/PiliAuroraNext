#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <shobjidl.h>

#include <optional>
#include <utility>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kMainInstanceMutex[] = L"Local\\PiliAuroraNext.MainInstance";
constexpr DWORD kActivationTimeoutMs = 5000;

HWND FindMainWindow() {
  HWND found = nullptr;
  ::EnumWindows([](HWND window, LPARAM context) -> BOOL {
    if (!::GetPropW(window, FlutterWindow::kMainWindowProperty)) return TRUE;
    *reinterpret_cast<HWND*>(context) = window;
    return FALSE;
  }, reinterpret_cast<LPARAM>(&found));
  return found;
}

class MainInstance {
 public:
  enum class Result { primary, redirected, failed };

  MainInstance()
      : mutex_(::CreateMutexW(nullptr, TRUE, kMainInstanceMutex)),
        owned_(mutex_ && ::GetLastError() != ERROR_ALREADY_EXISTS) {}
  ~MainInstance() {
    if (owned_) ::ReleaseMutex(mutex_);
    if (mutex_) ::CloseHandle(mutex_);
  }
  MainInstance(const MainInstance&) = delete;
  MainInstance& operator=(const MainInstance&) = delete;

  Result Enter() {
    if (!mutex_) return Result::failed;
    if (owned_) return Result::primary;

    const auto deadline = ::GetTickCount64() + kActivationTimeoutMs;
    do {
      if (const HWND window = FindMainWindow()) {
        DWORD process_id = 0;
        ::GetWindowThreadProcessId(window, &process_id);
        if (process_id) {
          ::AllowSetForegroundWindow(process_id);
          if (::PostMessageW(window, FlutterWindow::kActivateMainWindow, 0, 0)) {
            SendAppLink(window);
            return Result::redirected;
          }
        }
      }

      const DWORD wait = ::WaitForSingleObject(mutex_, 50);
      if (wait == WAIT_OBJECT_0 || wait == WAIT_ABANDONED) {
        owned_ = true;
        return Result::primary;
      }
      if (wait != WAIT_TIMEOUT) break;
    } while (::GetTickCount64() < deadline);
    return Result::failed;
  }

 private:
  const HANDLE mutex_;
  bool owned_;
};

// 必须晚于窗口和插件析构；S_FALSE 也需要配对一次 CoUninitialize。
class ScopedCOM {
 public:
  ScopedCOM() : result_(::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ~ScopedCOM() {
    if (SUCCEEDED(result_)) ::CoUninitialize();
  }
  ScopedCOM(const ScopedCOM&) = delete;
  ScopedCOM& operator=(const ScopedCOM&) = delete;
  bool initialized() const { return SUCCEEDED(result_); }

 private:
  const HRESULT result_;
};
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t* command_line, _In_ int show_command) {
  auto arguments = GetCommandLineArguments();
  const bool player_window = !arguments.empty() &&
      arguments.front() == "--piliauroranext-player-window";
  const bool decoder_test = !arguments.empty() &&
      arguments.front() == "--piliauroranext-decoder-test";
  const bool main_window = !player_window && !decoder_test;
  std::optional<MainInstance> main_instance;
  if (main_window) {
    const auto result = main_instance.emplace().Enter();
    if (result == MainInstance::Result::redirected) return EXIT_SUCCESS;
    if (result == MainInstance::Result::failed) return EXIT_FAILURE;
  }
  if (decoder_test) {
    // 测试驱动崩溃由父进程报告，不能被系统错误对话框阻塞。
    ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  const ScopedCOM com;
  if (!com.initialized()) {
    return EXIT_FAILURE;
  }

  // 主窗口和播放子进程共用任务栏应用标识；任务管理器分组由系统决定。
  if (FAILED(::SetCurrentProcessExplicitAppUserModelID(L"PiliAuroraNext.Desktop"))) {
    return EXIT_FAILURE;
  }

  flutter::DartProject project(L"data");

  // https://github.com/flutter/flutter/issues/188635
  // https://github.com/flutter/flutter/issues/191050
  // https://github.com/flutter/flutter/issues/191069
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  project.set_dart_entrypoint_arguments(std::move(arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(player_window ? L"PiliAuroraNext Player" : L"PiliAuroraNext",
                     origin, size)) {
    return EXIT_FAILURE;
  }
  if (main_window &&
      !::SetPropW(window.GetHandle(), FlutterWindow::kMainWindowProperty,
                  reinterpret_cast<HANDLE>(1))) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  return EXIT_SUCCESS;
}
