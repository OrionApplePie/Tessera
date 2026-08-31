import ApplicationServices
import CoreGraphics
import Foundation

/// Which windows are sitting in the Dock.
///
/// ScreenCaptureKit cannot tell a minimized window from one on another Space —
/// both are simply not on screen — and the difference matters: a minimized window
/// has no surface, so asking for its thumbnail hangs rather than failing.
/// Accessibility is the only public API that knows, which also means this degrades
/// to "nothing is minimized" when the permission is missing.
@MainActor
struct MinimizedWindowService {
  /// Accessibility round-trips are usually milliseconds, but a busy application
  /// can take far longer, and a timeout that is too tight silently reports it as
  /// having no minimized windows at all. Measured against a normal desktop, half a
  /// second was not enough; two seconds is, and an application that needs more than
  /// that is wedged rather than slow.
  private let messagingTimeout: Float

  private let logger: AppLogger

  init(config: AppConfig = .default) {
    self.messagingTimeout = Float(config.accessibilityTimeoutSeconds)
    self.logger = AppLogger(debugMode: config.debugMode, category: .capture)
  }

  /// Only applications with a window that is not on screen are asked: a window in
  /// plain sight is not minimized, and every question costs a round-trip.
  func minimizedWindows(forProcessIDs processIDs: Set<pid_t>) -> MinimizedWindows {
    guard AXIsProcessTrusted() else {
      logger.debug("Accessibility not granted; minimized windows cannot be told apart")
      return MinimizedWindows(titlesByProcessID: [:])
    }

    var titlesByProcessID: [pid_t: Set<String>] = [:]

    for processID in processIDs {
      let titles = minimizedTitles(processID: processID)
      guard !titles.isEmpty else {
        continue
      }

      titlesByProcessID[processID] = titles
    }

    return MinimizedWindows(titlesByProcessID: titlesByProcessID)
  }

  private func minimizedTitles(processID: pid_t) -> Set<String> {
    let application = AXUIElementCreateApplication(processID)
    AXUIElementSetMessagingTimeout(application, messagingTimeout)

    var windowsValue: CFTypeRef?
    let status = AXUIElementCopyAttributeValue(
      application,
      kAXWindowsAttribute as CFString,
      &windowsValue
    )

    guard status == .success, let windows = windowsValue as? [AXUIElement] else {
      return []
    }

    var titles: Set<String> = []

    for window in windows {
      var minimizedValue: CFTypeRef?
      var titleValue: CFTypeRef?

      guard
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimizedValue)
          == .success,
        (minimizedValue as? Bool) == true,
        AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleValue)
          == .success,
        let title = titleValue as? String,
        !title.isEmpty
      else {
        continue
      }

      titles.insert(title)
    }

    return titles
  }
}

/// The answer, separated from the Accessibility calls that produce it so the
/// lookup can be tested on its own.
struct MinimizedWindows: Sendable {
  private let titlesByProcessID: [pid_t: Set<String>]

  init(titlesByProcessID: [pid_t: Set<String>]) {
    self.titlesByProcessID = titlesByProcessID
  }

  /// Windows are matched by title, the same handle `WindowActivator` raises them
  /// by. An untitled window never matches: there is nothing to match it on, and
  /// guessing would mark the wrong window as minimized.
  func contains(processID: pid_t, title: String) -> Bool {
    guard !title.isEmpty else {
      return false
    }

    return titlesByProcessID[processID]?.contains(title) ?? false
  }
}
