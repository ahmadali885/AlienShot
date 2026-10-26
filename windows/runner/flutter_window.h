#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "recorder_channel.h"
#include "win32_window.h"

// Registered window message a second launch posts to the running copy, asking
// it to bring its window up (see main.cpp).
inline constexpr wchar_t kActivateMessageName[] = L"AlienWave.AlienShot.Activate";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Forwards activation requests from a second launch to Dart.
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> instance_channel_;
  UINT activate_message_ = 0;

  // Screen recording ("alienshot/recorder").
  std::unique_ptr<RecorderChannel> recorder_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
