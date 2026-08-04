import Cocoa
import FlutterMacOS

/// Dock-tile unread badge for macOS.
///
/// The native idiom is `NSApp.dockTile.badgeLabel`, a free-form string AppKit
/// draws in the red pill on the dock icon — so mentions become a numeral and
/// unread-without-mentions becomes a dot, with no icon compositing of our own.
/// Lives in the runner (rather than a plugin) because that is the entire
/// implementation; see `lib/features/notifications/services/taskbar_badge.dart`
/// for the caller.
enum TaskbarBadge {
  private static let channelName = "com.daccord.app/taskbar_badge"

  /// AppKit truncates nothing, so cap the label — a four-digit dock badge is
  /// unreadable and, past a point, the exact number stops mattering.
  private static let maxCount = 99

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "setBadge" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let arguments = call.arguments as? [String: Any]
      let count = arguments?["count"] as? Int ?? 0
      let visible = arguments?["visible"] as? Bool ?? false
      apply(count: count, visible: visible)
      result(nil)
    }
  }

  private static func apply(count: Int, visible: Bool) {
    let tile = NSApplication.shared.dockTile
    if count > 0 {
      tile.badgeLabel = count > maxCount ? "\(maxCount)+" : "\(count)"
    } else if visible {
      // No mentions but something is unread: a dot, matching Mail/Messages.
      tile.badgeLabel = "●"
    } else {
      tile.badgeLabel = nil
    }
    tile.display()
  }
}
