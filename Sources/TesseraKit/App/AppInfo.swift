import ApplicationServices
import CoreGraphics
import Foundation

/// What the About page reports.
///
/// The version lives here rather than in a bundle because this is a plain
/// executable and has no `Info.plist` to read one from. One place to change it,
/// named so that the packaging change which introduces a bundle can replace this
/// with the bundle's own value and nothing else.
enum AppInfo {
  static let version = "0.1.0"

  /// Both permissions are reported as the system answers them right now rather than
  /// as they were at launch: granting one does not restart the app, and someone
  /// looking at this page is usually looking because they have just granted it.
  static var screenRecordingStatus: String {
    CGPreflightScreenCaptureAccess()
      ? String(localized: "Granted") : String(localized: "Not granted — the list will be empty")
  }

  static var accessibilityStatus: String {
    AXIsProcessTrusted()
      ? String(localized: "Granted")
      : String(localized: "Not granted — only applications can be raised")
  }

  static var configurationDirectory: String {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/tessera")
      .path
  }
}
