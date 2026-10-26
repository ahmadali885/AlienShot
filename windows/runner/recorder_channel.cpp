#include "recorder_channel.h"

#include <flutter/standard_method_codec.h>

#include <string>

namespace {

RecorderChannel* g_instance = nullptr;

const flutter::EncodableValue* Arg(const flutter::EncodableMap& args, const char* key) {
  const auto it = args.find(flutter::EncodableValue(key));
  return it == args.end() ? nullptr : &it->second;
}

double ArgDouble(const flutter::EncodableMap& args, const char* key, double fallback = 0) {
  const auto* value = Arg(args, key);
  if (!value) return fallback;
  if (const auto* d = std::get_if<double>(value)) return *d;
  if (const auto* i = std::get_if<int32_t>(value)) return *i;
  if (const auto* l = std::get_if<int64_t>(value)) return static_cast<double>(*l);
  return fallback;
}

bool ArgBool(const flutter::EncodableMap& args, const char* key, bool fallback = false) {
  const auto* value = Arg(args, key);
  if (const auto* b = value ? std::get_if<bool>(value) : nullptr) return *b;
  return fallback;
}

std::string ArgString(const flutter::EncodableMap& args, const char* key) {
  const auto* value = Arg(args, key);
  if (const auto* s = value ? std::get_if<std::string>(value) : nullptr) return *s;
  return "";
}

std::string WideToUtf8(const std::wstring& text) {
  if (text.empty()) return "";
  const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0, nullptr, nullptr);
  std::string narrow(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), narrow.data(), length, nullptr, nullptr);
  return narrow;
}

std::wstring Utf8ToWide(const std::string& text) {
  if (text.empty()) return L"";
  const int length = MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0);
  std::wstring wide(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, text.data(), static_cast<int>(text.size()), wide.data(), length);
  return wide;
}

}  // namespace

RecorderChannel::RecorderChannel(flutter::BinaryMessenger* messenger, HWND window) : window_(window) {
  g_instance = this;
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "alienshot/recorder", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    HandleMethodCall(call, std::move(result));
  });
}

RecorderChannel::~RecorderChannel() {
  SetClickThrough(false);
  recorder_.Stop();
  g_instance = nullptr;
}

RECT RecorderChannel::ToScreen(double left, double top, double width, double height) const {
  const double scale = GetDpiForWindow(window_) / 96.0;
  POINT origin{0, 0};
  ClientToScreen(window_, &origin);
  RECT rect;
  rect.left = origin.x + static_cast<LONG>(left * scale + 0.5);
  rect.top = origin.y + static_cast<LONG>(top * scale + 0.5);
  rect.right = rect.left + static_cast<LONG>(width * scale + 0.5);
  rect.bottom = rect.top + static_cast<LONG>(height * scale + 0.5);
  return rect;
}

void RecorderChannel::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const std::string& method = call.method_name();

  if (method == "start") {
    if (!args) return result->Error("bad_args", "Expected a map");
    RecordingOptions options;
    options.region = ToScreen(ArgDouble(*args, "left"), ArgDouble(*args, "top"),
                              ArgDouble(*args, "width"), ArgDouble(*args, "height"));
    options.monitor_at_cursor = ArgBool(*args, "monitorAtCursor");
    options.fps = static_cast<int>(ArgDouble(*args, "fps", 30));
    options.output_height = static_cast<int>(ArgDouble(*args, "outputHeight", 0));
    const std::string codec = ArgString(*args, "codec");
    options.codec = codec == "h264" ? VideoCodec::kH264 : codec == "hevc" ? VideoCodec::kHevc : VideoCodec::kAuto;
    const std::string rate = ArgString(*args, "rateControl");
    options.rate_control = rate == "cbr" ? RateControl::kCbr : rate == "quality" ? RateControl::kQuality : RateControl::kVbr;
    options.bitrate_kbps = static_cast<int>(ArgDouble(*args, "bitrateKbps", 0));
    options.quality = static_cast<int>(ArgDouble(*args, "quality", 70));
    options.keyframe_seconds = static_cast<int>(ArgDouble(*args, "keyframeSeconds", 2));
    options.cursor = ArgBool(*args, "cursor", true);
    options.system_audio = ArgBool(*args, "systemAudio", true);
    options.microphone = ArgBool(*args, "microphone");
    options.system_audio_device = Utf8ToWide(ArgString(*args, "systemAudioDevice"));
    options.microphone_device = Utf8ToWide(ArgString(*args, "microphoneDevice"));
    options.path = Utf8ToWide(ArgString(*args, "path"));
    // Keep the overlay (controls, region outline, live annotations) out of
    // the video; the annotations go in through SetOverlay instead.
    SetWindowDisplayAffinity(window_, WDA_EXCLUDEFROMCAPTURE);
    RecordingInfo info;
    const std::string error = recorder_.Start(options, &info);
    if (!error.empty()) {
      SetWindowDisplayAffinity(window_, WDA_NONE);
      return result->Error("start_failed", error);
    }
    return result->Success(flutter::EncodableValue(flutter::EncodableMap{
        {flutter::EncodableValue("width"), flutter::EncodableValue(info.width)},
        {flutter::EncodableValue("height"), flutter::EncodableValue(info.height)},
        {flutter::EncodableValue("codec"), flutter::EncodableValue(info.codec)},
    }));
  }
  if (method == "pause") {
    recorder_.Pause();
    return result->Success();
  }
  if (method == "resume") {
    recorder_.Resume();
    return result->Success();
  }
  if (method == "stop") {
    const std::string error = recorder_.Stop();
    SetWindowDisplayAffinity(window_, WDA_NONE);
    if (!error.empty()) return result->Error("stop_failed", error);
    return result->Success();
  }
  if (method == "setOverlay") {
    if (!args) return result->Error("bad_args", "Expected a map");
    const auto* bytes = Arg(*args, "rgba");
    const auto* pixels = bytes ? std::get_if<std::vector<uint8_t>>(bytes) : nullptr;
    const int width = static_cast<int>(ArgDouble(*args, "width"));
    const int height = static_cast<int>(ArgDouble(*args, "height"));
    if (pixels && pixels->size() == static_cast<size_t>(width) * height * 4) {
      recorder_.SetOverlay(*pixels, width, height);
    } else {
      recorder_.SetOverlay({}, 0, 0);
    }
    return result->Success();
  }
  if (method == "listAudioDevices") {
    flutter::EncodableList list;
    for (const AudioDevice& device : ListAudioDevices()) {
      list.push_back(flutter::EncodableValue(flutter::EncodableMap{
          {flutter::EncodableValue("id"), flutter::EncodableValue(WideToUtf8(device.id))},
          {flutter::EncodableValue("name"), flutter::EncodableValue(WideToUtf8(device.name))},
          {flutter::EncodableValue("output"), flutter::EncodableValue(device.is_output)},
          {flutter::EncodableValue("default"), flutter::EncodableValue(device.is_default)},
      }));
    }
    return result->Success(flutter::EncodableValue(list));
  }
  if (method == "setClickThrough") {
    // {enabled, captureAll, rects: [left, top, width, height, ...]} in
    // logical client pixels.
    if (!args) return result->Error("bad_args", "Expected a map");
    capture_all_ = ArgBool(*args, "captureAll");
    interactive_rects_.clear();
    const auto* rects = Arg(*args, "rects");
    if (const auto* list = rects ? std::get_if<flutter::EncodableList>(rects) : nullptr) {
      for (size_t i = 0; i + 3 < list->size(); i += 4) {
        auto number = [&](size_t j) {
          const auto& v = (*list)[i + j];
          if (const auto* d = std::get_if<double>(&v)) return *d;
          if (const auto* n = std::get_if<int32_t>(&v)) return static_cast<double>(*n);
          return 0.0;
        };
        interactive_rects_.push_back(ToScreen(number(0), number(1), number(2), number(3)));
      }
    }
    SetClickThrough(ArgBool(*args, "enabled"));
    return result->Success();
  }
  result->NotImplemented();
}

void RecorderChannel::SetClickThrough(bool enabled) {
  if (enabled) {
    // Layered + transparent passes clicks to whatever is underneath; the
    // timer lifts "transparent" while the cursor is over a control.
    const LONG style = GetWindowLong(window_, GWL_EXSTYLE);
    SetWindowLong(window_, GWL_EXSTYLE, style | WS_EX_LAYERED);
    if (!timer_) timer_ = SetTimer(nullptr, 0, 30, &RecorderChannel::OnClickThroughTimer);
    UpdateClickThrough();
  } else {
    if (timer_) {
      KillTimer(nullptr, timer_);
      timer_ = 0;
    }
    const LONG style = GetWindowLong(window_, GWL_EXSTYLE);
    SetWindowLong(window_, GWL_EXSTYLE, style & ~(WS_EX_TRANSPARENT | WS_EX_LAYERED));
  }
}

void RecorderChannel::UpdateClickThrough() {
  bool interactive = capture_all_;
  if (!interactive) {
    POINT cursor;
    GetCursorPos(&cursor);
    for (const RECT& rect : interactive_rects_) {
      if (PtInRect(&rect, cursor)) {
        interactive = true;
        break;
      }
    }
  }
  const LONG style = GetWindowLong(window_, GWL_EXSTYLE);
  const bool transparent = (style & WS_EX_TRANSPARENT) != 0;
  if (interactive == transparent) {
    SetWindowLong(window_, GWL_EXSTYLE, interactive ? (style & ~WS_EX_TRANSPARENT) : (style | WS_EX_TRANSPARENT));
  }
}

void CALLBACK RecorderChannel::OnClickThroughTimer(HWND, UINT, UINT_PTR, DWORD) {
  if (g_instance) g_instance->UpdateClickThrough();
}
