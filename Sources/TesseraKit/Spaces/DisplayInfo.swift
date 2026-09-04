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

  /// Where a window lands when it is sent to another display.
  ///
  /// Its place is kept in proportion rather than in points: a window a third of the
  /// way across a wide screen belongs a third of the way across a narrow one, and
  /// copying the offset would leave it hanging off the edge. The proportion is of
  /// the room the window has to move in, not of the screen, so a window against the
  /// right edge arrives against the right edge whatever the two sizes are.
  ///
  /// A window too large for the display it arrives on is taken down to fit, keeping
  /// its shape. One that fits is not resized at all: sent across and back, a window
  /// should be the size it started.
  static func frame(_ frame: CGRect, movedFrom source: CGRect, to target: CGRect) -> CGRect {
    guard !target.isEmpty, !frame.isEmpty else {
      return frame
    }

    let scale = min(1, target.width / frame.width, target.height / frame.height)
    let size = CGSize(
      width: (frame.width * scale).rounded(), height: (frame.height * scale).rounded())
    let origin = CGPoint(
      x: target.minX + place(frame.minX - source.minX, in: source.width - frame.width)
        * max(0, target.width - size.width),
      y: target.minY + place(frame.minY - source.minY, in: source.height - frame.height)
        * max(0, target.height - size.height)
    )

    return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
  }

  /// How far along its room a window sits, from 0 at one edge to 1 at the other.
  /// A window with no room to move — as wide as the screen, or wider — is at the
  /// start of it.
  private static func place(_ offset: CGFloat, in room: CGFloat) -> CGFloat {
    guard room > 0 else {
      return 0
    }

    return min(1, max(0, offset / room))
  }

  /// Whether two displays stand side by side rather than one above the other.
  private func sharesRow(with other: DisplayInfo) -> Bool {
    let overlap = min(frame.maxY, other.frame.maxY) - max(frame.minY, other.frame.minY)
    guard overlap > 0 else {
      return false
    }

    return overlap >= min(frame.height, other.frame.height) / 2
  }

  /// The screen a display id names, for the times something has to be put on the
  /// same display as a window. Matched on the number AppKit publishes, which is the
  /// id ScreenCaptureKit uses.
  @MainActor
  /// The display a screen is, for the two AppKit answers that come as screens.
  static func displayID(of screen: NSScreen?) -> CGDirectDisplayID? {
    let number = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber

    return number.map { CGDirectDisplayID($0.uint32Value) }
  }

  static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
    NSScreen.screens.first { screen in
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber

      return number.map { CGDirectDisplayID($0.uint32Value) } == displayID
    }
  }

  /// The room a display offers a window, in the coordinates windows are placed in.
  ///
  /// `NSScreen.visibleFrame` is the screen with the menu bar and the Dock taken
  /// out, which is what a window filling "the screen" should get. AppKit measures
  /// it from the bottom left of the main screen and Accessibility measures windows
  /// from the top left, so it is flipped here rather than used as it comes — the
  /// mistake this file's own note warns about.
  @MainActor
  static func visibleBounds(of displayID: CGDirectDisplayID) -> CGRect? {
    guard let screen = screen(for: displayID), let primary = NSScreen.screens.first else {
      return nil
    }

    let visible = screen.visibleFrame

    return CGRect(
      x: visible.minX,
      y: primary.frame.maxY - visible.maxY,
      width: visible.width,
      height: visible.height
    )
  }

  /// A display name with the words that say nothing taken out.
  ///
  /// macOS calls the laptop's own screen "Built-in Retina Display", which is three
  /// words to say what one says, and next to an external display called "VQ27AQL1A"
  /// it made every heading on that side of the map twice as wide. What is left is
  /// what tells the displays apart.
  static func shortened(_ name: String) -> String {
    let noise: Set<String> = ["display", "displays", "retina", "monitor", "дисплей", "монитор"]
    let kept = name.split(separator: " ").filter { !noise.contains($0.lowercased()) }
    let short = kept.joined(separator: " ")

    return short.isEmpty ? name : short
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

      names[CGDirectDisplayID(number.uint32Value)] = shortened(screen.localizedName)
    }

    return names
  }
}
