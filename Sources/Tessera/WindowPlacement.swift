import CoreGraphics
import Foundation

/// Where a window is put on the screen it is already on.
///
/// The halves are what a person reaches for when two windows have to be read at
/// once, and filling the screen is the fourth: macOS calls that zooming, and its
/// own green button does it differently in every application. Doing it by
/// geometry means the same answer everywhere, and one that can be undone by asking
/// for a different one.
///
/// Fullscreen is deliberately not here. It is a mode rather than a rectangle — the
/// window gets a Space of its own and the menu bar goes away — so it is asked for
/// through Accessibility instead.
enum WindowPlacement: Equatable, Sendable, CaseIterable {
  case leftHalf
  case rightHalf
  case topHalf
  case bottomHalf
  case full

  /// The rectangle this placement means inside the room a screen offers.
  ///
  /// Rounded to whole points, and the far edge is taken from the far edge rather
  /// than from a doubled half: an odd width left a one-point seam down the middle
  /// of two windows placed side by side.
  func frame(in bounds: CGRect) -> CGRect {
    let midX = (bounds.minX + bounds.width / 2).rounded()
    let midY = (bounds.minY + bounds.height / 2).rounded()

    switch self {
    case .leftHalf:
      return CGRect(
        x: bounds.minX, y: bounds.minY, width: midX - bounds.minX, height: bounds.height)
    case .rightHalf:
      return CGRect(x: midX, y: bounds.minY, width: bounds.maxX - midX, height: bounds.height)
    case .topHalf:
      return CGRect(x: bounds.minX, y: bounds.minY, width: bounds.width, height: midY - bounds.minY)
    case .bottomHalf:
      return CGRect(x: bounds.minX, y: midY, width: bounds.width, height: bounds.maxY - midY)
    case .full:
      return bounds
    }
  }

  /// The placement an arrow asks for, or nothing when the map is what is being
  /// moved instead.
  static func inDirection(_ direction: OverlayGrid.Direction) -> WindowPlacement {
    switch direction {
    case .left:
      return .leftHalf
    case .right:
      return .rightHalf
    case .up:
      return .topHalf
    case .down:
      return .bottomHalf
    }
  }
}
