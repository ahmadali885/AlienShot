#ifndef RUNNER_RECORDER_CHANNEL_H_
#define RUNNER_RECORDER_CHANNEL_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <vector>

#include "screen_recorder.h"

// The "alienshot/recorder" channel: drives ScreenRecorder, and makes the
// recording overlay window click-through everywhere except its controls.
class RecorderChannel {
 public:
  RecorderChannel(flutter::BinaryMessenger* messenger, HWND window);
  ~RecorderChannel();

 private:
  void HandleMethodCall(const flutter::MethodCall<flutter::EncodableValue>& call,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // Logical pixels inside the window's client area -> physical screen pixels.
  RECT ToScreen(double left, double top, double width, double height) const;

  void SetClickThrough(bool enabled);
  void UpdateClickThrough();
  static void CALLBACK OnClickThroughTimer(HWND, UINT, UINT_PTR, DWORD);

  HWND window_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  ScreenRecorder recorder_;

  // Areas (screen pixels) that take the mouse while click-through is on.
  std::vector<RECT> interactive_rects_;
  // A drawing tool is active: the whole overlay takes the mouse.
  bool capture_all_ = false;
  UINT_PTR timer_ = 0;
};

#endif  // RUNNER_RECORDER_CHANNEL_H_
