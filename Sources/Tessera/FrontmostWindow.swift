import CoreGraphics
import Foundation

/// Which single window is in front.
///
/// Comparing process ids is not enough: two windows of one application share a
/// process, and marking both as frontmost is marking neither. What distinguishes
/// them is their order on screen, which `CGWindowListCopyWindowInfo` reports front
/// to back — the one public API that knows.
enum FrontmostWindow {
  struct Entry: Equatable {
    let windowID: CGWindowID
    let processID: pid_t
  }

  /// The first window of `processID` in front-to-back order that the switcher is
  /// also listing. `nil` when the frontmost application has no window on screen,
  /// which is what an application whose windows are all minimized looks like.
  static func identify(
    processID: pid_t?,
    among candidates: Set<CGWindowID>,
    frontToBack: [Entry]
  ) -> CGWindowID? {
    guard let processID else {
      return nil
    }

    return
      frontToBack
      .first { $0.processID == processID && candidates.contains($0.windowID) }?
      .windowID
  }

  /// On-screen windows in front-to-back order, as the window server sees them.
  ///
  /// Desktop elements are excluded; everything else is kept, because a window this
  /// list omits is a window that cannot be found to be frontmost.
  static func onScreenFrontToBack() -> [Entry] {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
      return []
    }

    return info.compactMap { window in
      guard
        let number = window[kCGWindowNumber as String] as? Int,
        let processID = window[kCGWindowOwnerPID as String] as? Int
      else {
        return nil
      }

      return Entry(windowID: CGWindowID(number), processID: pid_t(processID))
    }
  }
}
