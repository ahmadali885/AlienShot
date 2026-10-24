import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screen_capturer/screen_capturer.dart';
import 'package:win32/win32.dart';

class CaptureService {
  /// Grabs the primary screen straight into a [ui.Image].
  ///
  /// On Windows this goes through GDI directly (BitBlt + GetDIBits) and hands
  /// the raw BGRA pixels to the engine. The plugin path instead encodes a PNG,
  /// writes it to a temp file, reads it back and decodes it again — on a 4K
  /// display that round trip alone costs a second or more, which is what made
  /// the overlay feel sluggish compared to Lightshot.
  Future<ui.Image?> captureScreen() {
    if (Platform.isWindows) return _captureWindows();
    return _captureViaPlugin();
  }

  /// macOS gates screen capture behind a Screen Recording permission. Without
  /// it `screencapture` still "succeeds" but returns nothing but the desktop
  /// wallpaper, so this has to be checked before every capture rather than
  /// letting the user wonder why their screenshot is blank.
  Future<bool> ensureScreenCaptureAccess() async {
    if (!Platform.isMacOS) return true;
    if (await screenCapturer.isAccessAllowed()) return true;
    await screenCapturer.requestAccess();
    return false;
  }

  Future<ui.Image?> _captureWindows() async {
    final width = GetSystemMetrics(SM_CXSCREEN);
    final height = GetSystemMetrics(SM_CYSCREEN);
    if (width <= 0 || height <= 0) return null;

    final screenDC = GetDC(NULL);
    final memoryDC = CreateCompatibleDC(screenDC);
    final bitmap = CreateCompatibleBitmap(screenDC, width, height);
    final previousBitmap = SelectObject(memoryDC, bitmap);

    final byteCount = width * height * 4;
    final info = calloc<BITMAPINFO>();
    final buffer = calloc<Uint8>(byteCount);
    try {
      BitBlt(memoryDC, 0, 0, width, height, screenDC, 0, 0, SRCCOPY);
      // GetDIBits needs the bitmap unselected from the DC.
      SelectObject(memoryDC, previousBitmap);

      info.ref.bmiHeader
        ..biSize = sizeOf<BITMAPINFOHEADER>()
        ..biWidth = width
        // Negative height asks GDI for a top-down DIB, matching the row order
        // decodeImageFromPixels expects.
        ..biHeight = -height
        ..biPlanes = 1
        ..biBitCount = 32
        ..biCompression = BI_RGB;

      final rows = GetDIBits(
        memoryDC,
        bitmap,
        0,
        height,
        buffer.cast(),
        info,
        DIB_RGB_COLORS,
      );
      if (rows == 0) return null;

      // BitBlt from the screen leaves the alpha byte at zero, which would make
      // the whole frame render fully transparent — force every pixel opaque.
      // Done in place: copying the frame onto the Dart heap first cost another
      // 8 MB (33 MB at 4K) per capture that lingered until a GC.
      final words = buffer.cast<Uint32>().asTypedList(width * height);
      for (var i = 0; i < words.length; i++) {
        words[i] |= 0xFF000000;
      }

      // The engine copies the pixels while decoding; the buffer is freed
      // below only after the decode has completed.
      final completer = Completer<ui.Image>();
      ui.decodeImageFromPixels(
        buffer.asTypedList(byteCount),
        width,
        height,
        ui.PixelFormat.bgra8888,
        completer.complete,
      );
      return await completer.future;
    } finally {
      calloc.free(buffer);
      calloc.free(info);
      DeleteObject(bitmap);
      DeleteDC(memoryDC);
      ReleaseDC(NULL, screenDC);
    }
  }

  Future<ui.Image?> _captureViaPlugin() async {
    final tempDir = await getTemporaryDirectory();
    final imagePath =
        '${tempDir.path}${Platform.pathSeparator}alienshot_full_${DateTime.now().millisecondsSinceEpoch}.png';

    final data = await screenCapturer.capture(
      mode: CaptureMode.screen,
      imagePath: imagePath,
      copyToClipboard: false,
      silent: true,
    );

    final bytes = data?.imageBytes;
    if (bytes == null) return null;

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }
}

final captureService = CaptureService();
