#ifndef RUNNER_RECORDING_BORDER_H_
#define RUNNER_RECORDING_BORDER_H_

#include <windows.h>

// A thin coloured frame around the area being recorded, so it's obvious a
// recording is running — made of four strip windows along the inside of the
// area's edges. They are excluded from capture (so never in the video),
// ignore the mouse, never take focus, and cover only a few pixels, so
// nothing full screen sits over a game.
class RecordingBorder {
 public:
  RecordingBorder() = default;
  ~RecordingBorder();

  RecordingBorder(const RecordingBorder&) = delete;
  RecordingBorder& operator=(const RecordingBorder&) = delete;

  // `area` in screen pixels; `thickness` in pixels.
  void Show(const RECT& area, COLORREF color, int thickness);
  void SetColor(COLORREF color);
  void Hide();

 private:
  static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);

  HWND strips_[4] = {};
  HBRUSH brush_ = nullptr;
};

#endif  // RUNNER_RECORDING_BORDER_H_
