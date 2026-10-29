#include "recording_border.h"

namespace {

constexpr wchar_t kClassName[] = L"AlienShotRecordingBorder";

void RegisterBorderClass(WNDPROC procedure) {
  static bool registered = false;
  if (registered) return;
  WNDCLASSEXW window_class{sizeof(window_class)};
  window_class.lpfnWndProc = procedure;
  window_class.hInstance = GetModuleHandle(nullptr);
  window_class.lpszClassName = kClassName;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  registered = RegisterClassExW(&window_class) != 0;
}

}  // namespace

RecordingBorder::~RecordingBorder() { Hide(); }

LRESULT CALLBACK RecordingBorder::WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  switch (message) {
    case WM_NCHITTEST:
      return HTTRANSPARENT;
    case WM_ERASEBKGND: {
      RECT client;
      GetClientRect(window, &client);
      const auto brush = reinterpret_cast<HBRUSH>(GetWindowLongPtr(window, GWLP_USERDATA));
      if (brush) FillRect(reinterpret_cast<HDC>(wparam), &client, brush);
      return 1;
    }
    case WM_PAINT: {
      PAINTSTRUCT paint;
      BeginPaint(window, &paint);
      EndPaint(window, &paint);
      return 0;
    }
  }
  return DefWindowProc(window, message, wparam, lparam);
}

void RecordingBorder::Show(const RECT& area, COLORREF color, int thickness) {
  Hide();
  RegisterBorderClass(&RecordingBorder::WindowProc);
  brush_ = CreateSolidBrush(color);

  const int width = area.right - area.left;
  const int height = area.bottom - area.top;
  const RECT strips[4] = {
      {area.left, area.top, area.right, area.top + thickness},              // top
      {area.left, area.bottom - thickness, area.right, area.bottom},        // bottom
      {area.left, area.top, area.left + thickness, area.bottom},            // left
      {area.right - thickness, area.top, area.right, area.bottom},          // right
  };
  if (width <= thickness * 2 || height <= thickness * 2) return;

  for (int i = 0; i < 4; ++i) {
    const RECT& r = strips[i];
    // Layered + transparent: clicks go straight through to whatever is
    // underneath. Tool window + no-activate: no taskbar button, no focus.
    HWND strip = CreateWindowExW(
        WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED | WS_EX_TRANSPARENT,
        kClassName, L"", WS_POPUP, r.left, r.top, r.right - r.left, r.bottom - r.top, nullptr, nullptr,
        GetModuleHandle(nullptr), nullptr);
    if (!strip) continue;
    SetWindowLongPtr(strip, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(brush_));
    SetLayeredWindowAttributes(strip, 0, 235, LWA_ALPHA);
    // Seen by the user, never by screen capture — so not in the video.
    SetWindowDisplayAffinity(strip, WDA_EXCLUDEFROMCAPTURE);
    ShowWindow(strip, SW_SHOWNOACTIVATE);
    strips_[i] = strip;
  }
}

void RecordingBorder::SetColor(COLORREF color) {
  if (!brush_) return;
  HBRUSH replacement = CreateSolidBrush(color);
  for (HWND strip : strips_) {
    if (!strip) continue;
    SetWindowLongPtr(strip, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(replacement));
    InvalidateRect(strip, nullptr, TRUE);
  }
  DeleteObject(brush_);
  brush_ = replacement;
}

void RecordingBorder::Hide() {
  for (HWND& strip : strips_) {
    if (strip) DestroyWindow(strip);
    strip = nullptr;
  }
  if (brush_) {
    DeleteObject(brush_);
    brush_ = nullptr;
  }
}
