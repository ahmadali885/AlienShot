import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// True while the capture overlay is up. AppKit normally keeps titled
  /// windows below the menu bar and at normal level, which would leave the
  /// menu bar drawn over the top strip of the screenshot and unselectable.
  private var overlayMode = false

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "alienshot/macos",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      switch call.method {
      case "setOverlayMode":
        self.setOverlayMode((call.arguments as? Bool) ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private func setOverlayMode(_ on: Bool) {
    overlayMode = on
    level = on ? .screenSaver : .normal
    // The primary display (the one with the menu bar) is what gets captured.
    if on, let screen = NSScreen.screens.first {
      setFrame(screen.frame, display: true)
    }
  }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    return overlayMode ? frameRect : super.constrainFrameRect(frameRect, to: screen)
  }
}
