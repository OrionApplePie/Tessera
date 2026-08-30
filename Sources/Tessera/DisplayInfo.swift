import AppKit
import CoreGraphics
import Foundation

/// One physical display, in the coordinate space ScreenCaptureKit reports windows
/// in — origin at the top left of the main display, other screens at negative
/// coordinates if they sit above or to the left of it.
///
/// Deliberately not `NSScreen`: AppKit puts the origin at the bottom left, so
/// pairing its frames with `SCWindow.frame` would mean flipping every rectangle.
struct DisplayInfo: Identifiable, Hashable, Sendable {
  let id: CGDirectDisplayID
  let name: String
  let frame: CGRect

  /// The display a window belongs to: the one covering the largest part of it,
  /// which is the rule macOS itself uses for a window straddling two screens.
  /// On an exact tie the earlier display in `displays` wins.
  static func display(for windowFrame: CGRect, among displays: [DisplayInfo]) -> DisplayInfo? {
    var best: (display: DisplayInfo, area: CGFloat)?

    for display in displays {
      let overlap = display.frame.intersection(windowFrame)
      guard !overlap.isNull else {
        continue
      }

      let area = overlap.width * overlap.height
      guard area > 0, area > (best?.area ?? 0) else {
        continue
      }

      best = (display, area)
    }

    return best?.display
  }

  /// Section order in the overlay: the way the displays are actually arranged,
  /// top to bottom and then left to right. A monitor standing above the laptop
  /// gets the upper section, which is the only order that matches what the eye
  /// expects when it looks up from the keyboard.
  ///
  /// Displays are banded into rows first, because two screens side by side are
  /// almost never aligned to the pixel: comparing their top edges directly would
  /// let a few points of offset decide which one comes first. Screens sharing at
  /// least half the shorter one's height count as the same row.
  ///
  /// The order is fixed by geometry rather than by which display is main or which
  /// holds the focus, so sections do not reshuffle between refreshes.
  static func order(of displays: [DisplayInfo]) -> [CGDirectDisplayID] {
    let topToBottom = displays.sorted { first, second in
      if first.frame.minY != second.frame.minY {
        return first.frame.minY < second.frame.minY
      }

      if first.frame.minX != second.frame.minX {
        return first.frame.minX < second.frame.minX
      }

      return first.id < second.id
    }

    var rows: [[DisplayInfo]] = []
    for display in topToBottom {
      guard var row = rows.last, let previous = row.last, previous.sharesRow(with: display) else {
        rows.append([display])
        continue
      }

      row.append(display)
      rows[rows.count - 1] = row
    }

    return
      rows
      .flatMap { row in
        row.sorted { first, second in
          if first.frame.minX != second.frame.minX {
            return first.frame.minX < second.frame.minX
          }

          return first.id < second.id
        }
      }
      .map(\.id)
  }

  /// Whether two displays stand side by side rather than one above the other.
  private func sharesRow(with other: DisplayInfo) -> Bool {
    let overlap = min(frame.maxY, other.frame.maxY) - max(frame.minY, other.frame.minY)
    guard overlap > 0 else {
      return false
    }

    return overlap >= min(frame.height, other.frame.height) / 2
  }

  /// ScreenCaptureKit knows displays only by number. The name a person recognises
  /// comes from AppKit, matched on the same display id.
  @MainActor
  static func localizedNames() -> [CGDirectDisplayID: String] {
    var names: [CGDirectDisplayID: String] = [:]

    for screen in NSScreen.screens {
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      guard let number else {
        continue
      }

      names[CGDirectDisplayID(number.uint32Value)] = screen.localizedName
    }

    return names
  }
}
