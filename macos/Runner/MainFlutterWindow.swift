import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// True while the capture overlay is up. AppKit normally keeps titled
  /// windows below the menu bar and at normal level, which would leave the
  /// menu bar drawn over the top strip of the screenshot and unselectable.
  private var overlayMode = false

  /// The window's own style, put back when the overlay closes.
  private var savedStyleMask: NSWindow.StyleMask?
  private var savedFrame: NSRect?

  /// What the tray's "Take screenshot" item shows on its right, set from
  /// Dart whenever the capture shortcut changes.
  private var trayShortcut: (key: String, modifiers: NSEvent.ModifierFlags)?

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
      case "setTrayShortcut":
        let args = call.arguments as? [String: Any] ?? [:]
        self.setTrayShortcut(
          key: args["key"] as? String ?? "",
          modifiers: args["modifiers"] as? [String] ?? [])
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // tray_manager builds its NSMenu without key equivalents; fill in the
    // capture shortcut each time a menu opens, so it shows the way
    // Lightshot's "Take screenshot  ⌘." does.
    NotificationCenter.default.addObserver(
      forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
    ) { [weak self] note in
      guard let menu = note.object as? NSMenu else { return }
      self?.applyTrayShortcut(to: menu)
    }

    super.awakeFromNib()
  }

  // A borderless window can't become key by default, which would leave the
  // overlay deaf to Esc and every other key.
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }

  private func setOverlayMode(_ on: Bool) {
    guard on != overlayMode else { return }
    overlayMode = on
    if on {
      savedStyleMask = styleMask
      savedFrame = frame
      // Titled windows keep their frame, rounded corners and shadow, and
      // AppKit fits them inside the visible area — so the overlay showed up
      // as a smaller window in the middle of the screen. A borderless window
      // at screen-saver level covers the whole display, menu bar included.
      styleMask = [.borderless]
      hasShadow = false
      level = .screenSaver
      collectionBehavior.insert([.canJoinAllSpaces, .fullScreenAuxiliary])
      // The primary display (the one with the menu bar) is what gets captured.
      if let screen = NSScreen.screens.first {
        setFrame(screen.frame, display: true)
      }
      NSApp.activate(ignoringOtherApps: true)
      makeKeyAndOrderFront(nil)
    } else {
      level = .normal
      collectionBehavior.remove([.canJoinAllSpaces, .fullScreenAuxiliary])
      if let mask = savedStyleMask { styleMask = mask }
      hasShadow = true
      if let frame = savedFrame { setFrame(frame, display: true) }
    }
  }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    return overlayMode ? frameRect : super.constrainFrameRect(frameRect, to: screen)
  }

  private func setTrayShortcut(key: String, modifiers: [String]) {
    guard let equivalent = Self.keyEquivalent(key) else {
      trayShortcut = nil
      return
    }
    var flags: NSEvent.ModifierFlags = []
    for m in modifiers {
      switch m {
      case "control": flags.insert(.control)
      case "alt": flags.insert(.option)
      case "shift": flags.insert(.shift)
      case "meta": flags.insert(.command)
      default: break
      }
    }
    trayShortcut = (equivalent, flags)
  }

  private func applyTrayShortcut(to menu: NSMenu) {
    // Must match kMacCaptureItemLabel in lib/services/tray_service.dart.
    guard let item = menu.items.first(where: { $0.title == "Take screenshot" }) else { return }
    item.keyEquivalent = trayShortcut?.key ?? ""
    item.keyEquivalentModifierMask = trayShortcut?.modifiers ?? []
  }

  /// Dart sends a key's character, or "@name" for keys AppKit spells with a
  /// function-key code.
  private static func keyEquivalent(_ key: String) -> String? {
    if key.isEmpty { return nil }
    guard key.hasPrefix("@") else { return key }
    let name = String(key.dropFirst())
    var code: Int?
    if name.hasPrefix("f"), let n = Int(name.dropFirst()), (1...35).contains(n) {
      code = NSF1FunctionKey + n - 1
    } else {
      switch name {
      case "left": code = NSLeftArrowFunctionKey
      case "right": code = NSRightArrowFunctionKey
      case "up": code = NSUpArrowFunctionKey
      case "down": code = NSDownArrowFunctionKey
      case "home": code = NSHomeFunctionKey
      case "end": code = NSEndFunctionKey
      case "pageup": code = NSPageUpFunctionKey
      case "pagedown": code = NSPageDownFunctionKey
      case "fwddelete": code = NSDeleteFunctionKey
      default: code = nil
      }
    }
    guard let c = code, let scalar = UnicodeScalar(c) else { return nil }
    return String(Character(scalar))
  }
}
