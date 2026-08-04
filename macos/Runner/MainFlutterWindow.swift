import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Unread dock badge (see TaskbarBadge.swift) — registered here because it
    // needs the engine's messenger and nothing else.
    TaskbarBadge.register(with: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
