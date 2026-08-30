import Foundation

/// Keyboard navigation over the overlay's wrapped grid of tiles.
///
/// Kept apart from the SwiftUI view so the movement rules can be tested without
/// a window on screen.
enum OverlayGrid {
  /// Beyond this a row gets too wide for a laptop display, so tiles wrap.
  static let maximumColumns = 6

  enum Direction {
    case left
    case right
    case up
    case down
  }

  /// One column count for the whole overlay, so tiles line up down the sections
  /// instead of every section picking its own width.
  static func columnCount(forSectionSizes sizes: [Int]) -> Int {
    max(1, min(sizes.max() ?? 0, maximumColumns))
  }

  /// Flat tile indices laid out row by row, one section after another. A section
  /// always starts a new row, which is what makes a section boundary invisible to
  /// the movement rules below: it is simply the next row down.
  static func rows(forSectionSizes sizes: [Int]) -> [[Int]] {
    let columns = columnCount(forSectionSizes: sizes)
    var rows: [[Int]] = []
    var next = 0

    for size in sizes where size > 0 {
      var remaining = size

      while remaining > 0 {
        let taken = min(columns, remaining)
        rows.append(Array(next..<(next + taken)))
        next += taken
        remaining -= taken
      }
    }

    return rows
  }

  /// Where the highlight sits when the overlay opens: the first window that is not
  /// already frontmost, so pressing Return switches somewhere instead of
  /// re-activating what you are looking at.
  static func initialIndex(for tiles: [WindowTileModel]) -> Int {
    tiles.firstIndex { !$0.isActive } ?? 0
  }

  /// Left and right walk the tiles in reading order and wrap around the ends,
  /// crossing section boundaries as if the list were flat. Up and down move one
  /// row — into the neighbouring section when that is what is above or below — and
  /// stop at the very top and bottom: wrapping vertically over rows of different
  /// widths teleports the highlight somewhere the eye cannot follow.
  ///
  /// A shorter target row keeps the highlight in its last column rather than
  /// leaving it nowhere.
  static func index(from index: Int, moving direction: Direction, rows: [[Int]]) -> Int {
    let tileCount = rows.reduce(0) { $0 + $1.count }
    guard tileCount > 0 else {
      return 0
    }

    let current = min(max(index, 0), tileCount - 1)
    guard let row = rows.firstIndex(where: { $0.contains(current) }) else {
      return current
    }

    switch direction {
    case .left:
      return (current - 1 + tileCount) % tileCount

    case .right:
      return (current + 1) % tileCount

    case .up:
      guard row > 0 else {
        return current
      }

      return rows[row - 1][min(current - rows[row][0], rows[row - 1].count - 1)]

    case .down:
      guard row + 1 < rows.count else {
        return current
      }

      return rows[row + 1][min(current - rows[row][0], rows[row + 1].count - 1)]
    }
  }
}
