import CoreGraphics
import Foundation

/// Keyboard navigation over the overlay's wrapped grid of tiles.
///
/// Kept apart from the SwiftUI view so the movement rules can be tested without
/// a window on screen.
enum OverlayGrid {
  enum Direction {
    case left
    case right
    case up
    case down
  }

  /// One column count for the whole overlay, so tiles line up down the sections
  /// instead of every section picking its own width. A row never holds more than
  /// `maximum` tiles, which is what keeps the panel narrower than the screen.
  /// Where a panel of `size` sits on a screen whose usable area is `usable`.
  ///
  /// `nil` says the screen is not known well enough to place anything, which is
  /// the caller's cue to fall back to `NSWindow.center()`. Note that `usable` is
  /// not anchored at the origin on a second display: centring by width and height
  /// alone would put the panel on whichever screen happens to contain that point.
  static func placement(for size: CGSize, in usable: CGRect) -> CGRect? {
    guard usable.width > 0, usable.height > 0, size.width > 0, size.height > 0 else {
      return nil
    }

    return CGRect(
      x: usable.midX - size.width / 2,
      y: usable.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }

  static func columnCount(forSectionSizes sizes: [Int], maximum: Int) -> Int {
    max(1, min(sizes.max() ?? 0, max(1, maximum)))
  }

  /// The map's rows, as lists of Space numbers.
  ///
  /// The map is a grid whose cell is a Space, not a window: a row ends where the
  /// display ends, so each screen keeps its own band, and it ends again after
  /// `perRow` Spaces. Nothing is drawn between the bands — a display is where its
  /// Spaces are, which is what makes the map read like the desk the screens stand
  /// on.
  static func spaceRows(
    ofDisplays displays: [CGDirectDisplayID],
    perRow: Int,
    banded: Bool = true
  ) -> [[Int]] {
    let limit = max(1, perRow)

    // Without bands the Spaces are one sequence that wraps when the row is full:
    // where a window is stops being said by where it sits, which is the trade this
    // layout makes for fitting more of them in.
    guard banded else {
      return stride(from: 0, to: displays.count, by: limit).map {
        Array($0..<min($0 + limit, displays.count))
      }
    }

    var rows: [[Int]] = []
    var start = 0

    while start < displays.count {
      let display = displays[start]
      var end = start
      while end < displays.count, displays[end] == display {
        end += 1
      }

      rows.append(contentsOf: balanced(Array(start..<end), perRow: limit))
      start = end
    }

    return rows
  }

  /// A display's Spaces split into rows of as equal a length as they divide into.
  ///
  /// Six Spaces under a limit of five are three and three, not five and one: a band
  /// is read as a block, and a block with one lonely Space under a full row reads as
  /// a mistake rather than as a layout. With two displays it also keeps the two
  /// bands looking like each other, which is what makes the map symmetrical.
  private static func balanced(_ indices: [Int], perRow limit: Int) -> [[Int]] {
    guard indices.count > limit else {
      return indices.isEmpty ? [] : [indices]
    }

    let rows = Int((Double(indices.count) / Double(limit)).rounded(.up))
    let perRow = Int((Double(indices.count) / Double(rows)).rounded(.up))

    return stride(from: 0, to: indices.count, by: perRow).map {
      Array(indices[$0..<min($0 + perRow, indices.count)])
    }
  }

  /// The same map walked by Space rather than by window: the arrow lands on the
  /// first window of the Space it moves to, whatever was chosen in the Space it
  /// left.
  ///
  /// Which is what makes a map of Spaces navigable at all once a Space holds five
  /// windows: with the arrows walking windows, crossing the map meant pressing
  /// through every one of them.
  static func space(
    from index: Int,
    moving direction: Direction,
    sizes: [Int],
    rows: [[Int]]
  ) -> Int {
    let starts = starts(of: sizes)

    guard let total = starts.last.map({ $0 + (sizes.last ?? 0) }), total > 0 else {
      return index
    }

    let bounded = min(max(index, 0), total - 1)

    guard let space = sizes.indices.last(where: { starts[$0] <= bounded && sizes[$0] > 0 }),
      let row = rows.firstIndex(where: { $0.contains(space) }),
      let column = rows[row].firstIndex(of: space)
    else {
      return bounded
    }

    switch direction {
    case .left, .right:
      let step = direction == .right ? 1 : -1
      let next = column + step

      if rows[row].indices.contains(next) {
        return starts[rows[row][next]]
      }

      let other = rows[(row + rows.count + step) % rows.count]

      return starts[direction == .right ? other[0] : other[other.count - 1]]
    case .up, .down:
      let step = direction == .up ? rows.count - 1 : 1
      let other = rows[(row + step) % rows.count]

      return starts[other[min(column, other.count - 1)]]
    }
  }

  /// The next window inside the Space the highlight is already in, wrapping there
  /// rather than stepping out of it. This is what the cycling key does, and the only
  /// way to reach the windows behind the first one when the arrows count in Spaces.
  static func window(from index: Int, forward: Bool, sizes: [Int]) -> Int {
    let starts = starts(of: sizes)

    guard let total = starts.last.map({ $0 + (sizes.last ?? 0) }), total > 0 else {
      return index
    }

    let bounded = min(max(index, 0), total - 1)

    guard let space = sizes.indices.last(where: { starts[$0] <= bounded && sizes[$0] > 0 }) else {
      return bounded
    }

    let count = sizes[space]
    let depth = bounded - starts[space]

    return starts[space] + (depth + (forward ? 1 : count - 1)) % count
  }

  /// Where each Space's windows begin in the flat list the highlight indexes.
  private static func starts(of sizes: [Int]) -> [Int] {
    var starts: [Int] = []
    var next = 0

    for size in sizes {
      starts.append(next)
      next += size
    }

    return starts
  }

  /// Where the highlight goes, on a map whose cells are Spaces.
  ///
  /// Left and right deal through the cards of a Space and then step to the Space
  /// beside it; up and down move to the Space above or below, keeping the column
  /// and landing at the same depth in its deck where there is one. Both wrap: the
  /// map is a loop in each direction, so no arrow ever refuses to move.
  static func index(
    from index: Int,
    moving direction: Direction,
    sizes: [Int],
    rows: [[Int]]
  ) -> Int {
    var starts: [Int] = []
    var next = 0
    for size in sizes {
      starts.append(next)
      next += size
    }

    guard next > 0 else {
      return index
    }

    let bounded = min(max(index, 0), next - 1)

    guard
      let space = sizes.indices.last(where: { starts[$0] <= bounded && sizes[$0] > 0 }),
      let row = rows.firstIndex(where: { $0.contains(space) }),
      let column = rows[row].firstIndex(of: space)
    else {
      return bounded
    }

    let depth = bounded - starts[space]

    switch direction {
    case .left:
      if depth > 0 {
        return bounded - 1
      }

      // Off the front of a row is the end of the row above, not the end of this
      // one: left and right read the whole map in order and meet at its ends, so
      // the arrows never need the other axis to get anywhere.
      let previous =
        column > 0
        ? rows[row][column - 1]
        : rows[(row + rows.count - 1) % rows.count].last ?? space

      return starts[previous] + max(0, sizes[previous] - 1)
    case .right:
      if depth < sizes[space] - 1 {
        return bounded + 1
      }

      let next =
        column + 1 < rows[row].count
        ? rows[row][column + 1]
        : rows[(row + 1) % rows.count].first ?? space

      return starts[next]
    case .up, .down:
      let step = direction == .up ? rows.count - 1 : 1
      let other = rows[(row + step) % rows.count]
      let neighbour = other[min(column, other.count - 1)]

      return starts[neighbour] + min(depth, max(0, sizes[neighbour] - 1))
    }
  }

  /// Where the highlight sits when the overlay opens: on the window you are in.
  ///
  /// The accent fill already says which one that is, so starting the highlight
  /// there makes the two marks agree and gives the arrow keys an obvious origin —
  /// you move away from where you are, rather than from wherever the list happens
  /// to begin.
  /// A Space with nothing on it is the other place you can be standing, and then
  /// there is no window to mark. Opening the overlay from an empty desktop used to
  /// highlight the first tile in the list — some window on another Space — so the
  /// frame said "you are here" and the highlight said somewhere else.
  /// Where you stand comes first, and only then the active window. Standing on an
  /// empty desktop there is still an active window somewhere — the front
  /// application keeps one on the Space you came from, and it can even be a
  /// minimized one — and highlighting that put the mark on another Space entirely.
  static func initialIndex(for targets: [OverlayTarget], standingOn here: WindowSectionID?) -> Int {
    if let here, let index = targets.firstIndex(where: { $0.space == here }) {
      return index
    }

    return targets.firstIndex { $0.window?.isActive == true } ?? 0
  }

  /// What a letter is matched against.
  enum MatchField {
    case applicationName
    case windowTitle
  }

  /// The next tile whose name starts with `character`, wrapping around the list.
  ///
  /// Pressing the same letter again moves on to the next match, so a letter walks
  /// its own windows rather than always landing on the first of them. The search
  /// starts after the current tile for that reason.
  ///
  /// `nil` when no window carries that letter in that field, so the caller can try
  /// another reading of the same key press — or the same reading against the other
  /// field.
  static func index(
    from index: Int,
    matching character: Character,
    in tiles: [WindowTileModel],
    field: MatchField
  ) -> Int? {
    guard !tiles.isEmpty else {
      return nil
    }

    let current = min(max(index, 0), tiles.count - 1)
    let prefix = String(character).lowercased()

    let matches = tiles.indices.filter { position in
      let name =
        field == .applicationName
        ? tiles[position].displayAppName : tiles[position].displayTitle

      return name.lowercased().hasPrefix(prefix)
    }

    guard !matches.isEmpty else {
      return nil
    }

    return matches.first { $0 > current } ?? matches[0]
  }

}
