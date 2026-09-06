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

  /// The same, worked out from the configuration and the screen the map will open
  /// on: the ceiling is whichever is lower, what the configuration allows or what
  /// that screen can show without taking a tile below the size it is worth drawing.
  @MainActor
  static func budgets(
    forSections sections: [SpaceSection],
    config: AppConfig,
    on displayID: CGDirectDisplayID?
  ) -> [CGDirectDisplayID: Int] {
    let room = displayID.flatMap { DisplayInfo.visibleBounds(of: $0) }?.size ?? .zero

    return budgets(
      forSections: sections,
      cells: min(config.overlayMaxCells, cells(fitting: room, tile: config.overlayMinTile)),
      // Shared in whole rows where the row length is settled, and cell by cell
      // where the layout has yet to work it out.
      perRow: config.overlayLayout == .rows ? config.overlayColumns : 1
    )
  }

  /// How many cells each display may draw, in whole rows of the grid.
  ///
  /// Shared out rather than spent first-come: a grid of five across and four down
  /// is two rows a display, so one busy display cannot crowd the other off the map.
  /// The share is in rows rather than in cells because a band is drawn in rows — a
  /// budget of seven cells on a row of five would leave a band of two under a band
  /// of five and call it a share.
  static func budgets(
    forSections sections: [SpaceSection],
    cells total: Int,
    perRow: Int
  ) -> [CGDirectDisplayID: Int] {
    let columns = max(1, perRow)
    var displays: [CGDirectDisplayID] = []
    var wanted: [CGDirectDisplayID: Int] = [:]

    for section in sections {
      let id = section.id.displayID

      if wanted[id] == nil {
        displays.append(id)
      }

      wanted[id, default: 0] += 1
    }

    // Shared in whole rows where a row length is settled, and cell by cell where it
    // is not: a layout that works its own row length out has no rows to share yet.
    let units = max(1, total / columns)
    let rows = rows(sharing: units, between: displays.map { wanted[$0] ?? 0 }, perRow: columns)

    return Dictionary(uniqueKeysWithValues: zip(displays, rows.map { $0 * columns }))
  }

  /// How many cells go across when the shape follows the count.
  ///
  /// The square root, rounded up: nine Spaces make three rows of three, ten make
  /// four across and three down. A square map is the one whose tiles are largest
  /// for a given screen — a long row is limited by the width, a tall one by the
  /// height, and the square is where the two meet — and it keeps the map the same
  /// shape whatever is open, which a map that is read at a glance wants more than
  /// it wants the last few points of tile.
  static func columns(forCount count: Int) -> Int {
    let count = max(1, count)
    var columns = 1

    while columns * columns < count {
      columns += 1
    }

    return columns
  }

  /// How many cells of at least this size a screen can carry.
  ///
  /// Rough on purpose: gaps, headings and the surface's own padding are all
  /// fractions of the tile, so a cell is counted as the tile and a fifth. The
  /// layout that follows measures properly and shrinks what it must — this only
  /// says when the map should stop growing and start leaving Spaces off instead.
  ///
  /// A screen of no size is not a limit: nothing is known, so nothing is refused.
  static func cells(fitting room: CGSize, tile: CGFloat) -> Int {
    guard room.width > 0, room.height > 0, tile > 0 else {
      return .max
    }

    let cell = tile * 1.2

    return max(1, Int(room.width / cell) * Int(room.height / cell))
  }

  /// How the map's rows are shared out between the displays.
  ///
  /// The grid is the budget: five across and four down is twenty cells, and what a
  /// display gets is a whole number of rows of it — never four and a half — so the
  /// two bands stack squarely and a Space never sits half on the map. Even shares
  /// come first, which with two displays is the symmetry the map is read by; only a
  /// display that cannot fill its share hands the rest to the other, and then it
  /// goes over in whole rows too.
  ///
  /// `wanted` is how many cells each display would draw given the room, in the
  /// order the displays appear on the map, and the answer is rows in that same
  /// order. A grid with fewer rows than there are displays is given one row each
  /// rather than dropping a display: a display missing from the map cannot be
  /// switched to.
  static func rows(sharing total: Int, between wanted: [Int], perRow: Int) -> [Int] {
    guard !wanted.isEmpty else {
      return []
    }

    let columns = max(1, perRow)
    let needed = wanted.map { max(1, ($0 + columns - 1) / columns) }
    let total = max(needed.count, total)

    guard needed.reduce(0, +) > total else {
      return needed
    }

    let share = max(1, total / needed.count)
    var given = needed.map { min($0, share) }
    var left = total - given.reduce(0, +)

    // What the short bands did not use, one row at a time, so two displays wanting
    // more than the grid holds end up within a row of each other.
    while left > 0 {
      let before = left

      for index in given.indices where left > 0 && given[index] < needed[index] {
        given[index] += 1
        left -= 1
      }

      if left == before {
        break
      }
    }

    return given
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
  static func starts(of sizes: [Int]) -> [Int] {
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
  static func initialIndex(for targets: [OverlayTarget], standingOn here: SpaceSectionID?) -> Int {
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

  /// How much of a name a letter has to be at the start of.
  ///
  /// The whole name first, because that is what a letter usually means: "c" is
  /// Code. Then the start of any word in it, because a name is often two words and
  /// only one of them is the one anybody says — "Microsoft Excel" is Excel, and
  /// nobody presses "m" for it.
  enum MatchScope {
    case wholeName
    case anyWord
  }

  /// What ends a word inside a name.
  private static let wordBreaks = CharacterSet(charactersIn: " -_./·:,()[]—")

  /// Whether a name starts with this letter — the whole name, or any word of it.
  private static func starts(_ name: String, with prefix: String, scope: MatchScope) -> Bool {
    let name = name.lowercased()

    guard scope == .anyWord else {
      return name.hasPrefix(prefix)
    }

    return name.components(separatedBy: wordBreaks)
      .contains { !$0.isEmpty && $0.hasPrefix(prefix) }
  }

  /// Every place a letter names in one field, in the order they are drawn.
  static func matches(
    for character: Character,
    in targets: [OverlayTarget],
    field: MatchField,
    scope: MatchScope = .wholeName
  ) -> [Int] {
    let prefix = String(character).lowercased()

    return targets.indices.filter { position in
      guard let tile = targets[position].window else {
        return false
      }

      let name = field == .applicationName ? tile.displayAppName : tile.displayTitle

      return starts(name, with: prefix, scope: scope)
    }
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
  /// Counted over everything the highlight can sit on rather than over the windows
  /// alone: an empty Space is a place on the map too, and matching against a list
  /// that leaves those out returns a number that means a different tile by the time
  /// it reaches the highlight. One empty desktop earlier on the map was enough to
  /// land a letter on the window beside the one it named.
  static func index(
    from index: Int,
    matching character: Character,
    in targets: [OverlayTarget],
    field: MatchField,
    scope: MatchScope = .wholeName
  ) -> Int? {
    guard !targets.isEmpty else {
      return nil
    }

    let current = min(max(index, 0), targets.count - 1)
    let prefix = String(character).lowercased()

    let matches = targets.indices.filter { position in
      guard let tile = targets[position].window else {
        return false
      }

      let name = field == .applicationName ? tile.displayAppName : tile.displayTitle

      return starts(name, with: prefix, scope: scope)
    }

    guard !matches.isEmpty else {
      return nil
    }

    return matches.first { $0 > current } ?? matches[0]
  }

}
