import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    ShareBridge.shared.attach(to: flutterViewController)

    // How many notes are due, as a badge on the Dock icon.
    FlutterMethodChannel(
      name: "bilig/badge", binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setMethodCallHandler { call, result in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count = call.arguments as? Int ?? 0
      NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
      result(nil)
    }

    super.awakeFromNib()
  }
}

/// "New Bilig Note" in the Services menu (right-click selected text in any
/// app → Services): hands the text to Dart over the "bilig/share" channel,
/// the same one Android's share sheet uses.
class ShareBridge: NSObject {
  static let shared = ShareBridge()

  private var channel: FlutterMethodChannel?

  /// Text shared before Dart was listening (e.g. it launched the app).
  private var pending: String?

  func attach(to controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "bilig/share", binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "takeInitial" else {
        result(FlutterMethodNotImplemented)
        return
      }
      if let text = self?.pending {
        self?.pending = nil
        result(["text": text])
      } else {
        result(nil)
      }
    }
    self.channel = channel
  }

  /// The service entry point named by NSMessage in Info.plist.
  @objc func newNote(
    _ pboard: NSPasteboard, userData: String?,
    error: AutoreleasingUnsafeMutablePointer<NSString?>
  ) {
    guard let text = pboard.string(forType: .string),
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return }
    NSApp.activate(ignoringOtherApps: true)
    if let channel = channel {
      channel.invokeMethod("shared", arguments: ["text": text])
    } else {
      pending = text
    }
  }
}
