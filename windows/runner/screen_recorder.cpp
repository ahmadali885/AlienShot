#include "screen_recorder.h"

// <unknwn.h> before the C++/WinRT headers lets winrt::com_ptr / as<> work
// with classic COM interfaces such as IDirect3DDxgiInterfaceAccess.
#include <unknwn.h>

#include <audioclient.h>
#include <codecapi.h>
#include <d2d1_1.h>
#include <d3d11_4.h>
#include <dxgi1_2.h>
#include <mfapi.h>
#include <mferror.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <mmdeviceapi.h>
#include <mmreg.h>
#include <wrl/client.h>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Graphics.Capture.h>
#include <winrt/Windows.Graphics.DirectX.Direct3D11.h>
#include <windows.graphics.capture.interop.h>
#include <windows.graphics.directx.direct3d11.interop.h>

// Defines PKEY_Device_FriendlyName here (it is only declared otherwise).
#include <initguid.h>
#include <functiondiscoverykeys_devpkey.h>

#include <algorithm>
#include <atomic>
#include <cstdio>
#include <deque>
#include <mutex>
#include <thread>

using Microsoft::WRL::ComPtr;
namespace wgc = winrt::Windows::Graphics::Capture;
namespace wgd3d = winrt::Windows::Graphics::DirectX::Direct3D11;

namespace {

constexpr int64_t kTicksPerSecond = 10000000;  // Media Foundation's 100 ns units.
constexpr UINT32 kAudioRate = 48000;
constexpr UINT32 kAudioChannels = 2;
// Frames in flight between capture and encoder; the hardware encoder holds
// two or three at most.
constexpr int kTextureCount = 4;

std::string Fail(const char* what, HRESULT hr) {
  char buffer[160];
  std::snprintf(buffer, sizeof(buffer), "%s failed (0x%08lX)", what, static_cast<unsigned long>(hr));
  return buffer;
}

// QueryPerformanceCounter in 100 ns units — the same clock as
// Direct3D11CaptureFrame::SystemRelativeTime, so audio and video line up.
int64_t Now100ns() {
  LARGE_INTEGER count;
  LARGE_INTEGER frequency;
  QueryPerformanceCounter(&count);
  QueryPerformanceFrequency(&frequency);
  const int64_t q = count.QuadPart;
  const int64_t f = frequency.QuadPart;
  return (q / f) * kTicksPerSecond + (q % f) * kTicksPerSecond / f;
}

// Called when the encoder lets go of a frame, so its texture can be reused.
class SampleReleased : public IMFAsyncCallback {
 public:
  explicit SampleReleased(std::atomic<bool>* busy) : busy_(busy) {}

  STDMETHODIMP QueryInterface(REFIID riid, void** object) override {
    if (riid == __uuidof(IUnknown) || riid == __uuidof(IMFAsyncCallback)) {
      *object = static_cast<IMFAsyncCallback*>(this);
      AddRef();
      return S_OK;
    }
    *object = nullptr;
    return E_NOINTERFACE;
  }
  STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
  STDMETHODIMP_(ULONG) Release() override {
    const ULONG refs = --refs_;
    if (refs == 0) delete this;
    return refs;
  }
  STDMETHODIMP GetParameters(DWORD*, DWORD*) override { return E_NOTIMPL; }
  STDMETHODIMP Invoke(IMFAsyncResult*) override {
    busy_->store(false);
    return S_OK;
  }

 private:
  std::atomic<bool>* busy_;
  std::atomic<ULONG> refs_{1};
};

// One WASAPI endpoint — the speakers in loopback, or the microphone —
// converted to 48 kHz stereo float and queued for the mixer.
class AudioSource {
 public:
  ~AudioSource() { Close(); }

  // `device_id` empty: the Windows default for that direction.
  bool Open(bool loopback, const std::wstring& device_id) {
    ComPtr<IMMDeviceEnumerator> enumerator;
    ComPtr<IMMDevice> device;
    if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL,
                                IID_PPV_ARGS(&enumerator)))) {
      return false;
    }
    const HRESULT found = device_id.empty()
        ? enumerator->GetDefaultAudioEndpoint(loopback ? eRender : eCapture, eConsole, &device)
        : enumerator->GetDevice(device_id.c_str(), &device);
    if (FAILED(found) ||
        FAILED(device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                                reinterpret_cast<void**>(client_.GetAddressOf()))) ||
        FAILED(client_->GetMixFormat(&format_))) {
      return false;
    }
    if (FAILED(client_->Initialize(AUDCLNT_SHAREMODE_SHARED,
                                   loopback ? AUDCLNT_STREAMFLAGS_LOOPBACK : 0,
                                   kTicksPerSecond, 0, format_, nullptr)) ||
        FAILED(client_->GetService(IID_PPV_ARGS(&capture_))) || FAILED(client_->Start())) {
      return false;
    }
    channels_ = format_->nChannels;
    bits_ = format_->wBitsPerSample;
    WORD tag = format_->wFormatTag;
    if (tag == WAVE_FORMAT_EXTENSIBLE) {
      // The sub-format GUID starts with the plain format tag.
      tag = static_cast<WORD>(reinterpret_cast<WAVEFORMATEXTENSIBLE*>(format_)->SubFormat.Data1);
    }
    is_float_ = tag == WAVE_FORMAT_IEEE_FLOAT;
    step_ = static_cast<double>(format_->nSamplesPerSec) / kAudioRate;
    return channels_ > 0 && (is_float_ ? bits_ == 32 : (bits_ == 16 || bits_ == 24 || bits_ == 32));
  }

  void Close() {
    if (client_) client_->Stop();
    capture_.Reset();
    client_.Reset();
    if (format_) {
      CoTaskMemFree(format_);
      format_ = nullptr;
    }
  }

  // Drains whatever the device has captured into the queue.
  void Poll() {
    if (!capture_) return;
    UINT32 packet = 0;
    while (SUCCEEDED(capture_->GetNextPacketSize(&packet)) && packet > 0) {
      BYTE* data = nullptr;
      UINT32 frames = 0;
      DWORD flags = 0;
      if (FAILED(capture_->GetBuffer(&data, &frames, &flags, nullptr, nullptr))) return;
      const bool silent = (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0;
      for (UINT32 i = 0; i < frames; ++i) {
        const float left = silent ? 0.0f : Sample(data, i, 0);
        const float right = silent ? 0.0f : (channels_ > 1 ? Sample(data, i, 1) : left);
        pending_.push_back(left);
        pending_.push_back(right);
      }
      capture_->ReleaseBuffer(frames);
    }
    Resample();
  }

  // Adds up to `frames` queued frames into `mix`; missing ones are silence.
  void MixInto(float* mix, size_t frames) {
    const size_t samples = std::min(frames * kAudioChannels, queue_.size());
    for (size_t i = 0; i < samples; ++i) {
      mix[i] += queue_.front();
      queue_.pop_front();
    }
  }

  void Drop() {
    pending_.clear();
    queue_.clear();
    position_ = 0.0;
  }

 private:
  float Sample(const BYTE* data, UINT32 frame, int channel) const {
    const size_t index = static_cast<size_t>(frame) * channels_ + channel;
    if (is_float_) return reinterpret_cast<const float*>(data)[index];
    switch (bits_) {
      case 16:
        return reinterpret_cast<const int16_t*>(data)[index] / 32768.0f;
      case 24: {
        const BYTE* p = data + index * 3;
        const int32_t value = (p[0] << 8 | p[1] << 16 | p[2] << 24) >> 8;
        return value / 8388608.0f;
      }
      default:
        return static_cast<float>(reinterpret_cast<const int32_t*>(data)[index] / 2147483648.0);
    }
  }

  // Linear resampling from the device rate to 48 kHz.
  void Resample() {
    const size_t available = pending_.size() / kAudioChannels;
    while (position_ + 1 < available) {
      const size_t i = static_cast<size_t>(position_);
      const float t = static_cast<float>(position_ - i);
      for (size_t c = 0; c < kAudioChannels; ++c) {
        const float a = pending_[i * kAudioChannels + c];
        const float b = pending_[(i + 1) * kAudioChannels + c];
        queue_.push_back(a + (b - a) * t);
      }
      position_ += step_;
    }
    const size_t consumed = static_cast<size_t>(position_);
    if (consumed > 0) {
      pending_.erase(pending_.begin(), pending_.begin() + consumed * kAudioChannels);
      position_ -= consumed;
    }
    // A device clock running ahead of ours would grow the queue forever.
    const size_t limit = kAudioRate / 2 * kAudioChannels;
    while (queue_.size() > limit) queue_.pop_front();
  }

  ComPtr<IAudioClient> client_;
  ComPtr<IAudioCaptureClient> capture_;
  WAVEFORMATEX* format_ = nullptr;
  int channels_ = 0;
  int bits_ = 0;
  bool is_float_ = false;
  double step_ = 1.0;
  double position_ = 0.0;
  std::vector<float> pending_;
  std::deque<float> queue_;
};

}  // namespace

class ScreenRecorder::Impl {
 public:
  ~Impl() { Stop(); }

  std::string Start(const RecordingOptions& options, RecordingInfo* info) {
    if (recording_) return "Already recording";
    std::string error = StartInternal(options);
    if (!error.empty()) {
      Teardown();
    } else if (info) {
      info->width = static_cast<int>(width_);
      info->height = static_cast<int>(height_);
      info->codec = codec_name_;
    }
    return error;
  }

  void Pause() {
    if (!recording_ || paused_) return;
    pause_started_ = Now100ns();
    paused_ = true;
  }

  void Resume() {
    if (!recording_ || !paused_) return;
    paused_total_ += Now100ns() - pause_started_;
    paused_ = false;
  }

  std::string Stop() {
    if (!recording_) return "";
    if (paused_) Resume();
    recording_ = false;

    frame_revoker_.revoke();
    if (session_) session_.Close();
    if (frame_pool_) frame_pool_.Close();
    {
      // Wait out a frame that was already being handled.
      std::lock_guard<std::mutex> lock(frame_mutex_);
    }
    if (audio_thread_.joinable()) audio_thread_.join();

    std::string error;
    {
      std::lock_guard<std::mutex> lock(writer_mutex_);
      if (frames_written_ == 0) {
        error = "No video frames were captured";
      } else {
        const HRESULT hr = writer_->Finalize();
        if (FAILED(hr)) error = Fail("Finishing the video", hr);
      }
    }
    Teardown();
    return error;
  }

  bool IsRecording() const { return recording_; }

  void SetOverlay(std::vector<uint8_t> rgba, int width, int height) {
    std::lock_guard<std::mutex> lock(overlay_mutex_);
    overlay_pixels_ = std::move(rgba);
    overlay_width_ = width;
    overlay_height_ = height;
    overlay_dirty_ = true;
  }

 private:
  std::string StartInternal(const RecordingOptions& options) {
    HRESULT hr = MFStartup(MF_VERSION);
    if (FAILED(hr)) return Fail("Starting Media Foundation", hr);
    mf_started_ = true;

    // The monitor holding most of the region; the region is clipped to it.
    POINT cursor{};
    GetCursorPos(&cursor);
    HMONITOR monitor = options.monitor_at_cursor ? MonitorFromPoint(cursor, MONITOR_DEFAULTTOPRIMARY)
                                                 : MonitorFromRect(&options.region, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{sizeof(info)};
    if (!GetMonitorInfo(monitor, &info)) return "Couldn't find the monitor to record";
    const RECT area = options.monitor_at_cursor ? info.rcMonitor : options.region;
    RECT clipped;
    if (!IntersectRect(&clipped, &area, &info.rcMonitor)) {
      char message[160];
      std::snprintf(message, sizeof(message), "The area to record (%ld,%ld)-(%ld,%ld) is off screen",
                    options.region.left, options.region.top, options.region.right, options.region.bottom);
      return message;
    }
    // Encoders want even dimensions.
    const UINT32 area_width = static_cast<UINT32>((clipped.right - clipped.left) & ~1);
    const UINT32 area_height = static_cast<UINT32>((clipped.bottom - clipped.top) & ~1);
    if (area_width < 64 || area_height < 64) return "The area to record is too small";
    crop_ = {static_cast<UINT>(clipped.left - info.rcMonitor.left),
             static_cast<UINT>(clipped.top - info.rcMonitor.top), 0,
             static_cast<UINT>(clipped.left - info.rcMonitor.left) + area_width,
             static_cast<UINT>(clipped.top - info.rcMonitor.top) + area_height, 1};

    // Output size: the area's own, or the chosen height with the area's
    // aspect ratio (a 16:9 screen at "1440p" becomes exactly 2560x1440).
    if (options.output_height > 0) {
      height_ = static_cast<UINT32>(options.output_height) & ~1u;
      width_ = static_cast<UINT32>(static_cast<double>(area_width) * height_ / area_height + 0.5) & ~1u;
    } else {
      width_ = area_width;
      height_ = area_height;
    }
    scaling_ = width_ != area_width || height_ != area_height;
    fps_ = std::clamp(options.fps, 1, 120);
    frame_interval_ = kTicksPerSecond / fps_;

    // H.264 hardware encoders stop at 4096x2304; beyond that (8K) it's H.265.
    const bool beyond_h264 = width_ > 4096 || height_ > 4096 ||
                             static_cast<uint64_t>(width_) * height_ > 4096ull * 2304;
    hevc_ = options.codec == VideoCodec::kHevc || (options.codec == VideoCodec::kAuto && beyond_h264);
    if (!hevc_ && beyond_h264) return "H.264 can't encode above 4K. Choose H.265 (HEVC) or Auto for this resolution.";
    if (width_ > 8192 || height_ > 8192) return "The video would be larger than 8K";

    // --- Direct3D / Direct2D ---
    D3D_FEATURE_LEVEL level;
    hr = D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
                           D3D11_CREATE_DEVICE_BGRA_SUPPORT | D3D11_CREATE_DEVICE_VIDEO_SUPPORT,
                           nullptr, 0, D3D11_SDK_VERSION, &device_, &level, &context_);
    if (FAILED(hr)) return Fail("Creating the Direct3D device", hr);
    // Media Foundation's encoder uses the device from its own threads.
    if (SUCCEEDED(context_.As(&multithread_))) multithread_->SetMultithreadProtected(TRUE);

    ComPtr<IDXGIDevice> dxgi_device;
    device_.As(&dxgi_device);
    hr = D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d_factory_.GetAddressOf());
    if (SUCCEEDED(hr)) hr = d2d_factory_->CreateDevice(dxgi_device.Get(), &d2d_device_);
    if (SUCCEEDED(hr)) {
      hr = d2d_device_->CreateDeviceContext(D2D1_DEVICE_CONTEXT_OPTIONS_NONE, &d2d_context_);
    }
    if (FAILED(hr)) return Fail("Setting up Direct2D", hr);

    D3D11_TEXTURE2D_DESC desc{};
    desc.Width = width_;
    desc.Height = height_;
    desc.MipLevels = 1;
    desc.ArraySize = 1;
    desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    desc.SampleDesc.Count = 1;
    desc.Usage = D3D11_USAGE_DEFAULT;
    desc.BindFlags = D3D11_BIND_RENDER_TARGET | D3D11_BIND_SHADER_RESOURCE;
    const D2D1_BITMAP_PROPERTIES1 target_props = D2D1::BitmapProperties1(
        D2D1_BITMAP_OPTIONS_TARGET | D2D1_BITMAP_OPTIONS_CANNOT_DRAW,
        D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_PREMULTIPLIED));
    // An 8K frame is 130 MB; keep fewer of those in flight.
    texture_count_ = static_cast<uint64_t>(width_) * height_ > 3840ull * 2160 ? 3 : kTextureCount;
    for (int i = 0; i < texture_count_; ++i) {
      hr = device_->CreateTexture2D(&desc, nullptr, &textures_[i]);
      ComPtr<IDXGISurface> surface;
      if (SUCCEEDED(hr)) hr = textures_[i].As(&surface);
      if (SUCCEEDED(hr)) {
        hr = d2d_context_->CreateBitmapFromDxgiSurface(surface.Get(), &target_props, &targets_[i]);
      }
      if (FAILED(hr)) return Fail("Creating frame buffers", hr);
      busy_[i] = false;
    }

    if (scaling_) {
      // The area is cut out into this texture first, then Direct2D scales it
      // onto the output frame.
      D3D11_TEXTURE2D_DESC area_desc = desc;
      area_desc.Width = area_width;
      area_desc.Height = area_height;
      area_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
      hr = device_->CreateTexture2D(&area_desc, nullptr, &area_texture_);
      ComPtr<IDXGISurface> surface;
      if (SUCCEEDED(hr)) hr = area_texture_.As(&surface);
      if (SUCCEEDED(hr)) {
        // Screen pixels are opaque whatever their alpha byte says.
        const D2D1_BITMAP_PROPERTIES1 area_props = D2D1::BitmapProperties1(
            D2D1_BITMAP_OPTIONS_NONE, D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE));
        hr = d2d_context_->CreateBitmapFromDxgiSurface(surface.Get(), &area_props, &area_bitmap_);
      }
      if (FAILED(hr)) return Fail("Setting up scaling", hr);
    }

    // --- Audio sources (each optional; a missing mic isn't fatal) ---
    if (options.system_audio) {
      auto source = std::make_unique<AudioSource>();
      if (source->Open(true, options.system_audio_device)) audio_sources_.push_back(std::move(source));
    }
    if (options.microphone) {
      auto source = std::make_unique<AudioSource>();
      if (source->Open(false, options.microphone_device)) audio_sources_.push_back(std::move(source));
    }

    // --- Sink writer: hardware H.264 (+ AAC) into MP4 ---
    hr = MFCreateDXGIDeviceManager(&reset_token_, &device_manager_);
    if (SUCCEEDED(hr)) hr = device_manager_->ResetDevice(device_.Get(), reset_token_);
    if (FAILED(hr)) return Fail("Sharing the device with the encoder", hr);

    ComPtr<IMFAttributes> attributes;
    MFCreateAttributes(&attributes, 4);
    attributes->SetUnknown(MF_SINK_WRITER_D3D_MANAGER, device_manager_.Get());
    attributes->SetUINT32(MF_READWRITE_ENABLE_HARDWARE_TRANSFORMS, TRUE);
    attributes->SetGUID(MF_TRANSCODE_CONTAINERTYPE, MFTranscodeContainerType_MPEG4);
    hr = MFCreateSinkWriterFromURL(options.path.c_str(), nullptr, attributes.Get(), &writer_);
    if (FAILED(hr)) return Fail("Creating the video file", hr);

    // Automatic bitrate: screen content compresses well; ~0.12 bits per
    // pixel keeps text crisp in H.264, and H.265 needs about a third less.
    UINT32 bitrate = static_cast<UINT32>(std::max(options.bitrate_kbps, 0)) * 1000;
    if (bitrate == 0) {
      const double bits = static_cast<double>(width_) * height_ * fps_ * (hevc_ ? 0.08 : 0.12);
      bitrate = static_cast<UINT32>(std::clamp(bits, 4e6, 200e6));
    }
    const char* codec_name = hevc_ ? "H.265" : "H.264";

    ComPtr<IMFMediaType> video_out;
    MFCreateMediaType(&video_out);
    video_out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
    video_out->SetGUID(MF_MT_SUBTYPE, hevc_ ? MFVideoFormat_HEVC : MFVideoFormat_H264);
    video_out->SetUINT32(MF_MT_AVG_BITRATE, bitrate);
    video_out->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
    video_out->SetUINT32(MF_MT_MPEG2_PROFILE,
                         hevc_ ? static_cast<UINT32>(eAVEncH265VProfile_Main_420_8)
                               : static_cast<UINT32>(eAVEncH264VProfile_High));
    MFSetAttributeSize(video_out.Get(), MF_MT_FRAME_SIZE, width_, height_);
    MFSetAttributeRatio(video_out.Get(), MF_MT_FRAME_RATE, static_cast<UINT32>(fps_), 1);
    MFSetAttributeRatio(video_out.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
    hr = writer_->AddStream(video_out.Get(), &video_stream_);
    if (FAILED(hr)) {
      char message[200];
      std::snprintf(message, sizeof(message), "Your graphics card has no %s encoder for %ux%u (0x%08lX)",
                    codec_name, width_, height_, static_cast<unsigned long>(hr));
      return message;
    }

    // Rate control, bitrate/quality and keyframe spacing, as in OBS's
    // output settings. Not every encoder takes every option, so if these
    // are refused the encoder runs on its defaults instead.
    ComPtr<IMFAttributes> encoding;
    MFCreateAttributes(&encoding, 4);
    switch (options.rate_control) {
      case RateControl::kCbr:
        encoding->SetUINT32(CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_CBR);
        encoding->SetUINT32(CODECAPI_AVEncCommonMeanBitRate, bitrate);
        break;
      case RateControl::kVbr:
        encoding->SetUINT32(CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_UnconstrainedVBR);
        encoding->SetUINT32(CODECAPI_AVEncCommonMeanBitRate, bitrate);
        break;
      case RateControl::kQuality:
        encoding->SetUINT32(CODECAPI_AVEncCommonRateControlMode, eAVEncCommonRateControlMode_Quality);
        encoding->SetUINT32(CODECAPI_AVEncCommonQuality, static_cast<UINT32>(std::clamp(options.quality, 1, 100)));
        break;
    }
    encoding->SetUINT32(CODECAPI_AVEncMPVGOPSize,
                        static_cast<UINT32>(std::clamp(options.keyframe_seconds, 1, 10) * fps_));

    // Textures are top-down BGRA; the writer adds the GPU colour converter.
    hr = E_FAIL;
    for (IMFAttributes* parameters : {encoding.Get(), static_cast<IMFAttributes*>(nullptr)}) {
      for (const GUID& subtype : {MFVideoFormat_ARGB32, MFVideoFormat_RGB32}) {
        ComPtr<IMFMediaType> video_in;
        MFCreateMediaType(&video_in);
        video_in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Video);
        video_in->SetGUID(MF_MT_SUBTYPE, subtype);
        video_in->SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        video_in->SetUINT32(MF_MT_DEFAULT_STRIDE, width_ * 4);
        MFSetAttributeSize(video_in.Get(), MF_MT_FRAME_SIZE, width_, height_);
        MFSetAttributeRatio(video_in.Get(), MF_MT_FRAME_RATE, static_cast<UINT32>(fps_), 1);
        MFSetAttributeRatio(video_in.Get(), MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        hr = writer_->SetInputMediaType(video_stream_, video_in.Get(), parameters);
        if (SUCCEEDED(hr)) break;
      }
      if (SUCCEEDED(hr)) break;
    }
    if (FAILED(hr)) return Fail("Connecting frames to the encoder", hr);
    codec_name_ = codec_name;

    if (!audio_sources_.empty()) {
      ComPtr<IMFMediaType> audio_out;
      MFCreateMediaType(&audio_out);
      audio_out->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audio_out->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_AAC);
      audio_out->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioRate);
      audio_out->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
      audio_out->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
      audio_out->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, 24000);  // 192 kbps
      hr = writer_->AddStream(audio_out.Get(), &audio_stream_);
      if (FAILED(hr)) return Fail("Setting up the AAC encoder", hr);

      ComPtr<IMFMediaType> audio_in;
      MFCreateMediaType(&audio_in);
      audio_in->SetGUID(MF_MT_MAJOR_TYPE, MFMediaType_Audio);
      audio_in->SetGUID(MF_MT_SUBTYPE, MFAudioFormat_PCM);
      audio_in->SetUINT32(MF_MT_AUDIO_SAMPLES_PER_SECOND, kAudioRate);
      audio_in->SetUINT32(MF_MT_AUDIO_NUM_CHANNELS, kAudioChannels);
      audio_in->SetUINT32(MF_MT_AUDIO_BITS_PER_SAMPLE, 16);
      audio_in->SetUINT32(MF_MT_AUDIO_BLOCK_ALIGNMENT, kAudioChannels * 2);
      audio_in->SetUINT32(MF_MT_AUDIO_AVG_BYTES_PER_SECOND, kAudioRate * kAudioChannels * 2);
      hr = writer_->SetInputMediaType(audio_stream_, audio_in.Get(), nullptr);
      if (FAILED(hr)) return Fail("Connecting audio to the encoder", hr);
    }

    hr = writer_->BeginWriting();
    if (FAILED(hr)) return Fail("Starting the encoder", hr);

    // --- Windows.Graphics.Capture ---
    try {
      winrt::com_ptr<::IInspectable> inspectable;
      winrt::check_hresult(CreateDirect3D11DeviceFromDXGIDevice(dxgi_device.Get(), inspectable.put()));
      const auto capture_device = inspectable.as<wgd3d::IDirect3DDevice>();

      const auto interop = winrt::get_activation_factory<wgc::GraphicsCaptureItem, IGraphicsCaptureItemInterop>();
      wgc::GraphicsCaptureItem item{nullptr};
      winrt::check_hresult(interop->CreateForMonitor(
          monitor, winrt::guid_of<wgc::GraphicsCaptureItem>(), winrt::put_abi(item)));

      frame_pool_ = wgc::Direct3D11CaptureFramePool::CreateFreeThreaded(
          capture_device, winrt::Windows::Graphics::DirectX::DirectXPixelFormat::B8G8R8A8UIntNormalized,
          2, item.Size());
      session_ = frame_pool_.CreateCaptureSession(item);
      session_.IsCursorCaptureEnabled(options.cursor);
      try {
        // Windows 11: no yellow border around the captured screen.
        session_.IsBorderRequired(false);
      } catch (...) {
      }
      try {
        // Windows 11 24H2+: capture itself stops at our frame rate instead of
        // handing over every refresh of a 144 Hz screen to be thrown away.
        session_.MinUpdateInterval(winrt::Windows::Foundation::TimeSpan{frame_interval_});
      } catch (...) {
      }
      frame_revoker_ = frame_pool_.FrameArrived(winrt::auto_revoke, {this, &Impl::OnFrame});

      start_time_ = Now100ns();
      recording_ = true;
      session_.StartCapture();
    } catch (const winrt::hresult_error& e) {
      recording_ = false;
      return Fail("Starting screen capture", e.code());
    }

    if (!audio_sources_.empty()) audio_thread_ = std::thread([this] { AudioLoop(); });
    return "";
  }

  void Teardown() {
    recording_ = false;
    frame_revoker_.revoke();
    session_ = nullptr;
    frame_pool_ = nullptr;
    audio_sources_.clear();
    writer_.Reset();
    device_manager_.Reset();
    overlay_bitmap_.Reset();
    area_bitmap_.Reset();
    area_texture_.Reset();
    for (int i = 0; i < kTextureCount; ++i) {
      targets_[i].Reset();
      textures_[i].Reset();
    }
    d2d_context_.Reset();
    d2d_device_.Reset();
    d2d_factory_.Reset();
    multithread_.Reset();
    context_.Reset();
    device_.Reset();
    if (mf_started_) {
      MFShutdown();
      mf_started_ = false;
    }
    frames_written_ = 0;
    audio_frames_written_ = 0;
    last_video_time_ = -1;
    paused_ = false;
    paused_total_ = 0;
  }

  void OnFrame(const wgc::Direct3D11CaptureFramePool& sender, const winrt::Windows::Foundation::IInspectable&) {
    std::lock_guard<std::mutex> lock(frame_mutex_);
    const wgc::Direct3D11CaptureFrame frame = sender.TryGetNextFrame();
    if (!frame || !recording_ || paused_) return;

    const int64_t time = frame.SystemRelativeTime().count() - start_time_ - paused_total_;
    if (time < 0) return;
    // Cap the frame rate; also skips frames timestamped before a resume.
    if (last_video_time_ >= 0 && time < last_video_time_ + frame_interval_ * 9 / 10) return;

    int slot = -1;
    for (int i = 0; i < texture_count_; ++i) {
      bool expected = false;
      if (busy_[i].compare_exchange_strong(expected, true)) {
        slot = i;
        break;
      }
    }
    if (slot < 0) return;  // The encoder is behind; drop this frame.

    ComPtr<ID3D11Texture2D> source;
    try {
      const auto access = frame.Surface().as<::Windows::Graphics::DirectX::Direct3D11::IDirect3DDxgiInterfaceAccess>();
      winrt::check_hresult(access->GetInterface(IID_PPV_ARGS(&source)));
    } catch (...) {
      busy_[slot] = false;
      return;
    }

    if (multithread_) multithread_->Enter();
    // The monitor may have changed size; never read past its edge.
    D3D11_TEXTURE2D_DESC source_desc;
    source->GetDesc(&source_desc);
    D3D11_BOX box = crop_;
    box.right = std::min(box.right, static_cast<UINT>(source_desc.Width));
    box.bottom = std::min(box.bottom, static_cast<UINT>(source_desc.Height));
    if (box.right > box.left && box.bottom > box.top) {
      ID3D11Texture2D* destination = scaling_ ? area_texture_.Get() : textures_[slot].Get();
      context_->CopySubresourceRegion(destination, 0, 0, 0, 0, source.Get(), 0, &box);
    }
    Compose(slot);
    if (multithread_) multithread_->Leave();

    WriteVideo(slot, time);
  }

  // Finishes the frame in `slot`: the area scaled to the output size (when
  // it differs), then the annotation layer on top.
  void Compose(int slot) {
    {
      std::lock_guard<std::mutex> lock(overlay_mutex_);
      if (overlay_dirty_) {
        overlay_dirty_ = false;
        overlay_bitmap_.Reset();
        if (!overlay_pixels_.empty() && overlay_width_ > 0 && overlay_height_ > 0) {
          d2d_context_->CreateBitmap(
              D2D1::SizeU(static_cast<UINT32>(overlay_width_), static_cast<UINT32>(overlay_height_)),
              overlay_pixels_.data(), static_cast<UINT32>(overlay_width_) * 4,
              D2D1::BitmapProperties1(D2D1_BITMAP_OPTIONS_NONE,
                                      D2D1::PixelFormat(DXGI_FORMAT_R8G8B8A8_UNORM,
                                                        D2D1_ALPHA_MODE_PREMULTIPLIED)),
              &overlay_bitmap_);
        }
      }
    }
    if (!scaling_ && !overlay_bitmap_) return;
    d2d_context_->SetTarget(targets_[slot].Get());
    d2d_context_->BeginDraw();
    const D2D1_RECT_F dest = D2D1::RectF(0, 0, static_cast<float>(width_), static_cast<float>(height_));
    if (scaling_) {
      d2d_context_->DrawBitmap(area_bitmap_.Get(), &dest, 1.0f, D2D1_INTERPOLATION_MODE_HIGH_QUALITY_CUBIC);
    }
    if (overlay_bitmap_) {
      d2d_context_->DrawBitmap(overlay_bitmap_.Get(), &dest, 1.0f, D2D1_INTERPOLATION_MODE_LINEAR);
    }
    d2d_context_->EndDraw();
    d2d_context_->SetTarget(nullptr);
  }

  void WriteVideo(int slot, int64_t time) {
    ComPtr<IMFMediaBuffer> buffer;
    ComPtr<IMF2DBuffer> buffer_2d;
    ComPtr<IMFTrackedSample> tracked;
    ComPtr<IMFSample> sample;
    DWORD length = 0;
    HRESULT hr = MFCreateDXGISurfaceBuffer(__uuidof(ID3D11Texture2D), textures_[slot].Get(), 0, FALSE, &buffer);
    if (SUCCEEDED(hr)) hr = buffer.As(&buffer_2d);
    if (SUCCEEDED(hr)) hr = buffer_2d->GetContiguousLength(&length);
    if (SUCCEEDED(hr)) hr = buffer->SetCurrentLength(length);
    if (SUCCEEDED(hr)) hr = MFCreateTrackedSample(&tracked);
    if (SUCCEEDED(hr)) hr = tracked.As(&sample);
    if (SUCCEEDED(hr)) hr = sample->AddBuffer(buffer.Get());
    if (SUCCEEDED(hr)) {
      // Frees the slot once the encoder is done with the texture.
      auto* callback = new SampleReleased(&busy_[slot]);
      hr = tracked->SetAllocator(callback, nullptr);
      callback->Release();
    }
    if (SUCCEEDED(hr)) {
      sample->SetSampleTime(time);
      sample->SetSampleDuration(frame_interval_);
      std::lock_guard<std::mutex> lock(writer_mutex_);
      if (recording_) {
        hr = writer_->WriteSample(video_stream_, sample.Get());
        if (SUCCEEDED(hr)) {
          ++frames_written_;
          last_video_time_ = time;
        }
      }
    }
    if (FAILED(hr)) busy_[slot] = false;
  }

  // Mixes the audio sources against the wall clock: every tick writes
  // exactly the audio that should exist by now, so the track stays
  // continuous (loopback is silent — sends nothing — when nothing plays) and
  // in step with the video.
  void AudioLoop() {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    // A little behind real time, so late device packets still make it in.
    const int64_t latency = kTicksPerSecond / 20;
    std::vector<float> mix;
    std::vector<int16_t> pcm;
    while (recording_) {
      Sleep(10);
      for (auto& source : audio_sources_) source->Poll();
      if (paused_) {
        for (auto& source : audio_sources_) source->Drop();
        continue;
      }
      const int64_t elapsed = Now100ns() - start_time_ - paused_total_ - latency;
      if (elapsed <= 0) continue;
      const int64_t target = elapsed * kAudioRate / kTicksPerSecond;
      const int64_t frames = std::min<int64_t>(target - audio_frames_written_, kAudioRate);
      if (frames <= 0) continue;

      const size_t samples = static_cast<size_t>(frames) * kAudioChannels;
      mix.assign(samples, 0.0f);
      for (auto& source : audio_sources_) source->MixInto(mix.data(), static_cast<size_t>(frames));
      pcm.resize(samples);
      for (size_t i = 0; i < samples; ++i) {
        pcm[i] = static_cast<int16_t>(std::clamp(mix[i], -1.0f, 1.0f) * 32767.0f);
      }

      ComPtr<IMFMediaBuffer> buffer;
      const DWORD bytes = static_cast<DWORD>(samples * sizeof(int16_t));
      if (FAILED(MFCreateMemoryBuffer(bytes, &buffer))) continue;
      BYTE* data = nullptr;
      if (FAILED(buffer->Lock(&data, nullptr, nullptr))) continue;
      memcpy(data, pcm.data(), bytes);
      buffer->Unlock();
      buffer->SetCurrentLength(bytes);

      ComPtr<IMFSample> sample;
      if (FAILED(MFCreateSample(&sample))) continue;
      sample->AddBuffer(buffer.Get());
      sample->SetSampleTime(audio_frames_written_ * kTicksPerSecond / kAudioRate);
      sample->SetSampleDuration(frames * kTicksPerSecond / kAudioRate);
      {
        std::lock_guard<std::mutex> lock(writer_mutex_);
        if (recording_) writer_->WriteSample(audio_stream_, sample.Get());
      }
      audio_frames_written_ += frames;
    }
    CoUninitialize();
  }

  std::atomic<bool> recording_{false};
  std::atomic<bool> paused_{false};
  std::atomic<int64_t> paused_total_{0};
  int64_t pause_started_ = 0;
  int64_t start_time_ = 0;
  int64_t frame_interval_ = kTicksPerSecond / 30;
  int64_t last_video_time_ = -1;
  int64_t frames_written_ = 0;
  int64_t audio_frames_written_ = 0;
  int fps_ = 30;
  int texture_count_ = kTextureCount;
  bool scaling_ = false;
  bool hevc_ = false;
  const char* codec_name_ = "H.264";
  UINT32 width_ = 0;
  UINT32 height_ = 0;
  D3D11_BOX crop_{};
  bool mf_started_ = false;

  ComPtr<ID3D11Device> device_;
  ComPtr<ID3D11DeviceContext> context_;
  ComPtr<ID3D11Multithread> multithread_;
  ComPtr<ID2D1Factory1> d2d_factory_;
  ComPtr<ID2D1Device> d2d_device_;
  ComPtr<ID2D1DeviceContext> d2d_context_;
  ComPtr<ID3D11Texture2D> textures_[kTextureCount];
  ComPtr<ID2D1Bitmap1> targets_[kTextureCount];
  std::atomic<bool> busy_[kTextureCount];

  UINT reset_token_ = 0;
  ComPtr<IMFDXGIDeviceManager> device_manager_;
  ComPtr<IMFSinkWriter> writer_;
  DWORD video_stream_ = 0;
  DWORD audio_stream_ = 0;
  std::mutex writer_mutex_;
  std::mutex frame_mutex_;

  std::vector<std::unique_ptr<AudioSource>> audio_sources_;
  std::thread audio_thread_;

  std::mutex overlay_mutex_;
  std::vector<uint8_t> overlay_pixels_;
  int overlay_width_ = 0;
  int overlay_height_ = 0;
  bool overlay_dirty_ = false;
  ComPtr<ID2D1Bitmap1> overlay_bitmap_;
  ComPtr<ID3D11Texture2D> area_texture_;
  ComPtr<ID2D1Bitmap1> area_bitmap_;

  wgc::Direct3D11CaptureFramePool frame_pool_{nullptr};
  wgc::GraphicsCaptureSession session_{nullptr};
  wgc::Direct3D11CaptureFramePool::FrameArrived_revoker frame_revoker_;
};

ScreenRecorder::ScreenRecorder() : impl_(std::make_unique<Impl>()) {}
ScreenRecorder::~ScreenRecorder() = default;

std::string ScreenRecorder::Start(const RecordingOptions& options, RecordingInfo* info) {
  return impl_->Start(options, info);
}
void ScreenRecorder::Pause() { impl_->Pause(); }
void ScreenRecorder::Resume() { impl_->Resume(); }
std::string ScreenRecorder::Stop() { return impl_->Stop(); }
bool ScreenRecorder::IsRecording() const { return impl_->IsRecording(); }
void ScreenRecorder::SetOverlay(std::vector<uint8_t> rgba, int width, int height) {
  impl_->SetOverlay(std::move(rgba), width, height);
}

std::vector<AudioDevice> ListAudioDevices() {
  std::vector<AudioDevice> devices;
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr, CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return devices;
  }
  for (const EDataFlow flow : {eRender, eCapture}) {
    std::wstring default_id;
    ComPtr<IMMDevice> default_device;
    if (SUCCEEDED(enumerator->GetDefaultAudioEndpoint(flow, eConsole, &default_device))) {
      LPWSTR id = nullptr;
      if (SUCCEEDED(default_device->GetId(&id))) {
        default_id = id;
        CoTaskMemFree(id);
      }
    }
    ComPtr<IMMDeviceCollection> collection;
    UINT count = 0;
    if (FAILED(enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE, &collection)) ||
        FAILED(collection->GetCount(&count))) {
      continue;
    }
    for (UINT i = 0; i < count; ++i) {
      ComPtr<IMMDevice> device;
      LPWSTR id = nullptr;
      if (FAILED(collection->Item(i, &device)) || FAILED(device->GetId(&id))) continue;
      AudioDevice entry;
      entry.id = id;
      CoTaskMemFree(id);
      entry.is_output = flow == eRender;
      entry.is_default = entry.id == default_id;
      ComPtr<IPropertyStore> properties;
      if (SUCCEEDED(device->OpenPropertyStore(STGM_READ, &properties))) {
        PROPVARIANT name;
        PropVariantInit(&name);
        if (SUCCEEDED(properties->GetValue(PKEY_Device_FriendlyName, &name)) && name.vt == VT_LPWSTR) {
          entry.name = name.pwszVal;
        }
        PropVariantClear(&name);
      }
      devices.push_back(std::move(entry));
    }
  }
  return devices;
}
