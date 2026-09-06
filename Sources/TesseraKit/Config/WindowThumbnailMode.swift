import CoreGraphics
import Foundation

/// What a tile shows of a window.
///
/// A window scaled into a tile turns its text into grey texture, which is enough
/// to tell two applications apart and not enough to tell two documents apart. The
/// corner modes trade the shape of the window for a readable piece of it, and
/// differ only in how big a piece.
enum WindowThumbnailMode: Equatable, Sendable, CaseIterable {
  /// The whole window, scaled down to the tile.
  case fit
  /// The top left corner, the size of the tile itself, drawn at 1:1. The sharpest
  /// of the three, and the least of the window.
  case corner
  /// The top left corner, twice the tile across and down — four times the area,
  /// drawn at half size. Text is still legible on a Retina display.
  case cornerDouble
  /// Roughly a quarter of the window's area, in the tile's shape, scaled to fit.
  /// Enough to recognise a document by its layout rather than by its first line.
  case quarter
  /// Three quarters of the window's area: nearly the whole thing, with the last
  /// quarter — usually the empty right and bottom edges — left out, so what is left
  /// is drawn that much larger.
  case threeQuarters

  init(parsing text: String) throws {
    switch text.trimmingCharacters(in: .whitespaces).lowercased() {
    case "fit", "whole", "window":
      self = .fit
    case "corner", "crop", "top-left", "top_left":
      self = .corner
    case "corner2x", "corner-2x", "corner_2x", "double":
      self = .cornerDouble
    case "quarter", "fourth":
      self = .quarter
    case "75", "75%", "three-quarters", "three_quarters":
      self = .threeQuarters
    default:
      throw WindowThumbnailModeError.unknown(text)
    }
  }

  var name: String {
    switch self {
    case .fit:
      return "fit"
    case .corner:
      return "corner"
    case .cornerDouble:
      return "corner2x"
    case .quarter:
      return "quarter"
    case .threeQuarters:
      return "75"
    }
  }

  /// Whether a window is long enough that a piece of it says nothing about which
  /// window it is.
  ///
  /// A crop keeps the tile's proportions, so a tall narrow window is cropped to its
  /// top and a wide flat one to its left end — and the shape is the very thing that
  /// identifies such a window at a glance. Measured on a 338 by 612 window: three
  /// quarters of it in a tile's shape is its top 56 per cent.
  ///
  /// The threshold is the window's own sides and not a comparison with the tile,
  /// which was the first attempt and caught nothing: a tile is drawn landscape
  /// — 360 by 274 with its label — so a ratio against it put the bar at 2.4 and the
  /// window that prompted all this sat at 1.8. Measured on this desktop, ordinary
  /// windows run from 1.40 to 1.60 and the long ones start at 1.8, so 1.7 divides
  /// them with room on both sides.
  static func isLong(_ window: CGSize, ratio: CGFloat = 1.7) -> Bool {
    guard window.width > 0, window.height > 0 else {
      return false
    }

    return max(window.width / window.height, window.height / window.width) >= ratio
  }

  /// The mode a particular window is actually captured with: the one asked for,
  /// unless the window is long and the setting says to take those whole.
  static func capturing(
    _ window: CGSize,
    wanted: WindowThumbnailMode,
    takingLongWindowsWhole: Bool
  ) -> WindowThumbnailMode {
    guard takingLongWindowsWhole, isLong(window) else {
      return wanted
    }

    return .fit
  }

  /// The piece of a window this mode captures, in points, keeping the tile's own
  /// proportions so that the view has nothing left to crop and the top left corner
  /// is what actually reaches the screen.
  ///
  /// Never larger than the window: a window smaller than the piece asked for is
  /// taken whole and scaled up, which is the honest answer for a small window.
  func crop(ofWindow window: CGSize, tile: CGSize) -> CGSize {
    let wanted = CGSize(
      width: tile.width * magnification(ofWindow: window, tile: tile),
      height: tile.height * magnification(ofWindow: window, tile: tile)
    )

    return CGSize(
      width: min(wanted.width, max(window.width, 1)),
      height: min(wanted.height, max(window.height, 1))
    )
  }

  /// How many times the tile's own size the captured piece is.
  ///
  /// A quarter is worked out from the window rather than fixed: a quarter of a
  /// large window is a large piece, and of a small one a small piece, which is what
  /// "a quarter" means to the person reading the tile.
  private func magnification(ofWindow window: CGSize, tile: CGSize) -> CGFloat {
    switch self {
    case .fit, .corner:
      return 1
    case .cornerDouble:
      return 2
    case .quarter, .threeQuarters:
      let share = self == .quarter ? 0.25 : 0.75
      let tileArea = max(tile.width * tile.height, 1)
      let wantedArea = max(window.width * window.height, 0) * share
      return max(1, (wantedArea / tileArea).squareRoot())
    }
  }
}

enum WindowThumbnailModeError: Error, Equatable, CustomStringConvertible {
  case unknown(String)

  var description: String {
    switch self {
    case .unknown(let text):
      return "\"\(text)\" is not a thumbnail mode; expected fit, corner, corner2x or quarter"
    }
  }
}
