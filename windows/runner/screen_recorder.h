#ifndef RUNNER_SCREEN_RECORDER_H_
#define RUNNER_SCREEN_RECORDER_H_

#include <windows.h>

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

enum class VideoCodec { kAuto, kH264, kHevc };
enum class RateControl { kCbr, kVbr, kQuality };

struct RecordingOptions {
  // Area to record, in physical pixels of the virtual desktop. It is clipped
  // to the monitor that contains most of it.
  RECT region{};
  // Ignore `region` and record the whole monitor under the mouse cursor
  // (the record hotkey: no window has to be on screen for it).
  bool monitor_at_cursor = false;
  // Output height (e.g. 1080, 1440, 2160, 4320); the width follows the
  // area's aspect ratio. 0 records at the area's own size.
  int output_height = 0;
  int fps = 30;
  // kAuto: H.264 up to 4096 px, H.265 beyond (8K needs it).
  VideoCodec codec = VideoCodec::kAuto;
  RateControl rate_control = RateControl::kVbr;
  int bitrate_kbps = 0;  // 0 = chosen from size and frame rate
  int quality = 70;      // 1-100, for RateControl::kQuality
  int keyframe_seconds = 2;
  bool cursor = true;
  bool system_audio = true;
  bool microphone = false;
  // Endpoint IDs from ListAudioDevices(); empty means the Windows default.
  std::wstring system_audio_device;
  std::wstring microphone_device;
  std::wstring path;
};

// What Start() actually set up, for showing in the UI.
struct RecordingInfo {
  int width = 0;
  int height = 0;
  std::string codec;  // "H.264" or "H.265"
};

struct AudioDevice {
  std::wstring id;
  std::wstring name;
  bool is_output = false;  // speakers/headphones (recorded in loopback)
  bool is_default = false;
};

// Active speakers and microphones, for the settings' device pickers.
std::vector<AudioDevice> ListAudioDevices();

// Records part of one monitor to an H.264 + AAC MP4.
//
// Everything heavy stays on the GPU: Windows.Graphics.Capture hands over
// frames as D3D11 textures, the region is cut out and the annotation layer
// drawn on with Direct2D on the same device, and Media Foundation's hardware
// encoder takes the texture directly — no frame is ever copied through system
// memory, which is what keeps 4K recording cheap.
class ScreenRecorder {
 public:
  ScreenRecorder();
  ~ScreenRecorder();

  ScreenRecorder(const ScreenRecorder&) = delete;
  ScreenRecorder& operator=(const ScreenRecorder&) = delete;

  // Returns an empty string on success, or what went wrong. On success
  // `info` (if given) describes the file being written.
  std::string Start(const RecordingOptions& options, RecordingInfo* info = nullptr);
  void Pause();
  void Resume();
  // Finishes the file. Returns an empty string on success.
  std::string Stop();
  bool IsRecording() const;

  // The annotation layer drawn over every frame: RGBA with premultiplied
  // alpha, any size (it is scaled to the recorded area). Empty clears it.
  void SetOverlay(std::vector<uint8_t> rgba, int width, int height);

 private:
  class Impl;
  std::unique_ptr<Impl> impl_;
};

#endif  // RUNNER_SCREEN_RECORDER_H_
