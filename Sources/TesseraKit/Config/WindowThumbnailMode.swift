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

  /// Whether a window is so far from the tile's shape that a piece of it says
  /// nothing about which window it is.
  ///
  /// A crop keeps the tile's proportions, and a tile is square — so a tall narrow
  /// window is cropped to its top and a wide flat one to its left end. Measured on
  /// a 338x612 window, three quarters of it in a square is its top third: the
  /// shape, which is the thing that identifies such a window at a glance, is
  /// exactly what gets cut off. Whole is the honest answer there.
  ///
  /// The threshold is a ratio against the tile's own, so it means "much longer than
  /// what it is drawn in" rather than a number of points.
  static func isLong(_ window: CGSize, comparedTo tile: CGSize, ratio: CGFloat = 1.8) -> Bool {
    guard window.width > 0, window.height > 0, tile.width > 0, tile.height > 0 else {
      return false
    }

    let windowSides = max(window.width / window.height, window.height / window.width)
    let tileSides = max(tile.width / tile.height, tile.height / tile.width)

    return windowSides >= tileSides * ratio
  }

  /// The mode a particular window is actually captured with: the one asked for,
  /// unless the window is long and the setting says to take those whole.
  static func capturing(
    _ window: CGSize,
    wanted: WindowThumbnailMode,
    tile: CGSize,
    takingLongWindowsWhole: Bool
  ) -> WindowThumbnailMode {
    guard takingLongWindowsWhole, isLong(window, comparedTo: tile) else {
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
