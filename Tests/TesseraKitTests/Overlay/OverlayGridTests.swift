import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("OverlayGrid")
struct OverlayGridTests {
  @Test("A row holds up to six tiles and never fewer than one")
  func columnCountIsCappedAtSix() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [], maximum: 6) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [0], maximum: 6) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [3], maximum: 6) == 3)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 6) == 6)
  }

  @Test("The configured maximum caps the row, and one is the floor")
  func maximumCapsTheRow() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 4) == 4)
    #expect(OverlayGrid.columnCount(forSectionSizes: [3], maximum: 4) == 3)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: 0) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13], maximum: -2) == 1)
  }

  /// What a screen can carry at a given tile size, which is the other half of the
  /// ceiling: the configuration says at most so many, and the screen says at most
  /// so many more.
  @Test("A screen carries as many cells as fit at the smallest tile")
  func countsWhatTheScreenCanCarry() {
    let room = CGSize(width: 1512, height: 944)

    // 150-point tiles, counted as 180 with their gaps and headings: eight across,
    // five down. At 400 points a laptop screen carries three, in one row — which is
    // the point of the floor: the map stops growing rather than going unreadable.
    #expect(OverlayGrid.cells(fitting: room, tile: 150) == 40)
    #expect(OverlayGrid.cells(fitting: room, tile: 400) == 3)
  }

  /// A screen nobody could measure is not a limit: nothing is known, so nothing is
  /// refused.
  @Test("An unknown screen refuses nothing")
  func anUnknownScreenIsNoLimit() {
    #expect(OverlayGrid.cells(fitting: .zero, tile: 150) == .max)
    #expect(OverlayGrid.cells(fitting: CGSize(width: 100, height: 100), tile: 0) == .max)
  }

  /// A square map is the one whose tiles come out largest: a long row runs out of
  /// width, a tall one out of height, and the square is where they meet.
  @Test("The row length follows the square root of the count")
  func squaresTheMapByItsCount() {
    #expect(OverlayGrid.columns(forCount: 1) == 1)
    #expect(OverlayGrid.columns(forCount: 2) == 2)
    #expect(OverlayGrid.columns(forCount: 4) == 2)
    #expect(OverlayGrid.columns(forCount: 5) == 3)
    #expect(OverlayGrid.columns(forCount: 9) == 3)
    #expect(OverlayGrid.columns(forCount: 10) == 4)
    #expect(OverlayGrid.columns(forCount: 20) == 5)
  }

  /// A map of nothing is still drawn, and it is one cell wide.
  @Test("A count of none is a row of one")
  func squaresAnEmptyMap() {
    #expect(OverlayGrid.columns(forCount: 0) == 1)
    #expect(OverlayGrid.columns(forCount: -3) == 1)
  }

  /// The grid is the budget, and a display's share of it is whole rows: a display
  /// drawing four and a half rows would put a band of two under a band of five and
  /// call it a share.
  @Test("Two displays wanting more than the grid holds split its rows evenly")
  func sharesTheRowsEvenly() {
    #expect(OverlayGrid.rows(sharing: 4, between: [10, 10], perRow: 5) == [2, 2])
    #expect(OverlayGrid.rows(sharing: 4, between: [30, 30], perRow: 5) == [2, 2])
  }

  /// Symmetry is the first answer, not the only one: a share a display cannot use
  /// is better spent on the display that can.
  @Test("What a short band does not use goes to the other display, in whole rows")
  func handsTheUnusedRowsOver() {
    #expect(OverlayGrid.rows(sharing: 4, between: [20, 3], perRow: 5) == [3, 1])
    #expect(OverlayGrid.rows(sharing: 4, between: [2, 2], perRow: 5) == [1, 1])
  }

  /// An odd number of rows cannot be split evenly, and the extra one goes to a
  /// display that can fill it rather than being left undrawn.
  @Test("An odd grid leaves the two bands within a row of each other")
  func splitsAnOddGrid() {
    #expect(OverlayGrid.rows(sharing: 5, between: [20, 20], perRow: 5) == [3, 2])
  }

  /// A display missing from the map cannot be switched to, so a grid too short for
  /// the displays overflows rather than dropping one.
  @Test("Every display gets a row, even when the grid has fewer than there are")
  func neverDropsADisplay() {
    #expect(OverlayGrid.rows(sharing: 1, between: [5, 5, 5], perRow: 5) == [1, 1, 1])
    #expect(OverlayGrid.rows(sharing: 4, between: [], perRow: 5) == [])
  }

  /// The map's cell is a Space, and a row is a band of one display: measured on a
  /// machine whose built-in screen holds six Spaces and whose external holds three.
  ///
  /// The six are split three and three rather than five and one. A band reads as a
  /// block, and a block with one Space stranded under a full row reads as a mistake
  /// rather than as a layout — and with two displays the even split is what makes
  /// the two bands look like each other.
  @Test("A row is a band of one display, split evenly")
  func spacesAreBandedByDisplay() {
    let displays: [CGDirectDisplayID] = [1, 1, 1, 1, 1, 1, 2, 2, 2]

    #expect(
      OverlayGrid.spaceRows(ofDisplays: displays, perRow: 5) == [
        [0, 1, 2], [3, 4, 5], [6, 7, 8],
      ]
    )
  }

  @Test("A band longer than two rows still divides evenly")
  func longBandsDivideEvenly() {
    let displays: [CGDirectDisplayID] = Array(repeating: 1, count: 7)

    #expect(
      OverlayGrid.spaceRows(ofDisplays: displays, perRow: 3) == [
        [0, 1, 2], [3, 4, 5], [6],
      ]
    )
  }

  @Test("A display never shares a row with another one")
  func displaysKeepTheirOwnRows() {
    #expect(OverlayGrid.spaceRows(ofDisplays: [1, 2], perRow: 5) == [[0], [1]])
    #expect(OverlayGrid.spaceRows(ofDisplays: [], perRow: 5).isEmpty)
    #expect(OverlayGrid.spaceRows(ofDisplays: [1, 1], perRow: 0) == [[0], [1]])
  }

  @Test("Every section shares the widest section's column count")
  func columnCountIsSharedAcrossSections() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 5], maximum: 6) == 5)
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 9], maximum: 6) == 6)
  }

  @Test("A screen fits as many tiles across as there is room for")
  func countsTheColumnsAScreenFits() {
    // 190pt tiles, 14pt apart, inside 28pt of surface on each side.
    #expect(TileMetrics.base.columnsFitting(availableWidth: 1512) == 7)
    #expect(TileMetrics.base.columnsFitting(availableWidth: 2560) == 12)
    #expect(TileMetrics.base.columnsFitting(availableWidth: 860) == 4)
  }

  @Test("A screen too narrow for one tile still gets one")
  func neverFitsFewerThanOneColumn() {
    #expect(TileMetrics.base.columnsFitting(availableWidth: 100) == 1)
    #expect(TileMetrics.base.columnsFitting(availableWidth: 0) == 1)
  }

  @Test("The highlight starts on the window you are in")
  func initialIndexIsTheActiveWindow() {
    let targets = [makeTile(id: 1), makeTile(id: 2, isActive: true), makeTile(id: 3)]
      .map(OverlayTarget.window)

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 1)
  }

  @Test("With no window frontmost the highlight falls back to the first tile")
  func initialIndexFallsBackToZero() {
    let targets = [makeTile(id: 1), makeTile(id: 2)].map(OverlayTarget.window)

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 0)
    #expect(OverlayGrid.initialIndex(for: [], standingOn: nil) == 0)
  }

  /// While you are in a window there is no Space to stand on: the Space you are in
  /// holds that window, so it is drawn as tiles and never as a place of its own.
  @Test("In a window, the highlight starts on the window")
  func initialIndexPrefersTheActiveWindow() {
    let elsewhere = SpaceSectionID(displayID: 1, spaceIndex: 2)
    let targets: [OverlayTarget] = [
      .space(elsewhere), .window(makeTile(id: 1, isActive: true)),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 1)
  }

  /// Standing on an empty desktop there is still an active window somewhere — the
  /// front application keeps one on the Space you came from, and it can even be
  /// minimized. Marking that one put "you are here" on another Space.
  @Test("Standing on an empty Space beats an active window somewhere else")
  func initialIndexBeatsAnActiveWindowElsewhere() {
    let here = SpaceSectionID(displayID: 1, spaceIndex: 2)
    let targets: [OverlayTarget] = [
      .window(makeTile(id: 1, isActive: true)), .space(here),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: here) == 1)
  }

  /// This test used to assert the opposite, on the grounds that you are always in a
  /// window and never in a gap. That stopped being true when an empty desktop
  /// became somewhere you can go: standing on one, there is no window to mark, and
  /// the highlight belongs on the Space you are actually on rather than on the
  /// first tile of the list, which is a window on some other Space.
  @Test("Standing on an empty Space, the highlight starts there")
  func initialIndexIsTheSpaceYouStandOn() {
    let here = SpaceSectionID(displayID: 1, spaceIndex: 2)
    let elsewhere = SpaceSectionID(displayID: 1, spaceIndex: 3)
    let targets: [OverlayTarget] = [
      .window(makeTile(id: 1)), .space(elsewhere), .space(here),
    ]

    #expect(OverlayGrid.initialIndex(for: targets, standingOn: here) == 2)
    #expect(OverlayGrid.initialIndex(for: targets, standingOn: nil) == 0)
  }

  /// One Space of thirteen windows: left and right deal through its deck and wrap
  /// at its ends, because a row of one Space has nowhere else to go.
  @Test("Left and right deal through a Space and wrap")
  func horizontalMovementWalksADeck() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 0, moving: .right, sizes: [13], rows: rows) == 1)
    #expect(OverlayGrid.index(from: 7, moving: .left, sizes: [13], rows: rows) == 6)
    #expect(OverlayGrid.index(from: 12, moving: .right, sizes: [13], rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, sizes: [13], rows: rows) == 12)
  }

  /// Past the last card of a Space is the Space beside it, and coming back the
  /// other way lands on that neighbour's last card rather than its first.
  @Test("Left and right step to the Space beside this one")
  func horizontalMovementStepsBetweenSpaces() {
    let sizes = [3, 2]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1], perRow: 5)

    #expect(OverlayGrid.index(from: 2, moving: .right, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .left, sizes: sizes, rows: rows) == 2)
  }

  /// The end of a row is the start of the next one, and the end of the last row is
  /// the start of the first: right and left walk the whole map and close the loop.
  /// Confined to its own row, right stopped at the edge of a band and only down
  /// carried on, which is not what an arrow that has always wrapped should do.
  @Test("Right off the end of a row lands at the start of the next one")
  func horizontalMovementCrossesRows() {
    let sizes = [2, 2, 2]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2], perRow: 2)

    #expect(rows == [[0, 1], [2]])
    #expect(OverlayGrid.index(from: 3, moving: .right, sizes: sizes, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .left, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 5, moving: .right, sizes: sizes, rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, sizes: sizes, rows: rows) == 5)
  }

  /// Up and down are the other axis of the map: the Space above or below, in the
  /// same column, at the same depth in its deck.
  @Test("Up and down move to the Space above or below")
  func verticalMovementMovesBetweenBands() {
    let sizes = [3, 3, 3, 3]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2, 2], perRow: 5)

    #expect(rows == [[0, 1], [2, 3]])
    #expect(OverlayGrid.index(from: 1, moving: .down, sizes: sizes, rows: rows) == 7)
    #expect(OverlayGrid.index(from: 7, moving: .up, sizes: sizes, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 4, moving: .down, sizes: sizes, rows: rows) == 10)
  }

  /// A band with fewer Spaces has no column to match, so the highlight lands in its
  /// last one; a shallower deck has no card at that depth, so it lands on its last.
  @Test("A shorter band and a shallower deck both keep the highlight inside")
  func verticalMovementClampsToWhatIsThere() {
    let sizes = [2, 2, 1]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 1, 2], perRow: 5)

    #expect(OverlayGrid.index(from: 3, moving: .down, sizes: sizes, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .up, sizes: sizes, rows: rows) == 0)
  }

  /// This used to stop at the edges. Held down, that reads as an overlay which has
  /// stopped responding — which is how it was reported — and it disagreed with left
  /// and right, which have always wrapped.
  @Test("The top and bottom bands wrap into each other, so an arrow never dead-ends")
  func verticalMovementWrapsAtTheEdges() {
    let sizes = [3, 3]
    let rows = OverlayGrid.spaceRows(ofDisplays: [1, 2], perRow: 5)

    #expect(OverlayGrid.index(from: 0, moving: .up, sizes: sizes, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .down, sizes: sizes, rows: rows) == 0)
  }

  @Test("A single band wraps onto itself rather than refusing to move")
  func verticalMovementInOneBand() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 1, moving: .down, sizes: [3], rows: rows) == 1)
    #expect(OverlayGrid.index(from: 1, moving: .up, sizes: [3], rows: rows) == 1)
  }

  @Test("An out-of-range starting index is brought back in bounds")
  func clampsAnOutOfRangeIndex() {
    let rows = OverlayGrid.spaceRows(ofDisplays: [1], perRow: 5)

    #expect(OverlayGrid.index(from: 99, moving: .right, sizes: [3], rows: rows) == 0)
    #expect(OverlayGrid.index(from: -4, moving: .right, sizes: [3], rows: rows) == 1)
  }

  @Test("With no tiles every direction is a no-op")
  func emptyGridDoesNotMove() {
    for direction in [OverlayGrid.Direction.left, .right, .up, .down] {
      #expect(OverlayGrid.index(from: 0, moving: direction, sizes: [], rows: []) == 0)
    }
  }

  @Test("An out-of-range index does not stop a jump")
  func jumpClampsTheStartingIndex() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(
      OverlayGrid.index(
        from: 99, matching: "a", in: tiles.map(OverlayTarget.window), field: .applicationName) == 0)
  }

  private func makeTile(
    id: CGWindowID,
    isActive: Bool = false,
    appName: String = "Finder",
    title: String = "Downloads"
  ) -> WindowTile {
    WindowTile(
      id: id,
      appName: appName,
      title: title,
      processID: 100,
      isActive: isActive,
      isMinimized: false,
      displayID: 1,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }
}

@Suite("OverlayGrid placement")
struct OverlayGridPlacementTests {
  /// The second display in the layout this was measured on sits above and to the
  /// left of the built-in one, so its usable area starts at a negative x and a
  /// positive y. Centring that forgot the origin would land the panel on the
  /// built-in screen instead.
  private static let external = CGRect(x: -485, y: 982, width: 2560, height: 1415)

  @Test("A panel is centred in the usable area of the screen it opens on")
  func centresOnTheScreenGiven() throws {
    let placed = try #require(
      OverlayGrid.placement(for: CGSize(width: 858, height: 1312), in: Self.external))

    #expect(placed.midX == Self.external.midX)
    #expect(placed.midY == Self.external.midY)
    #expect(placed.size == CGSize(width: 858, height: 1312))
  }

  @Test("A panel wider than the screen is still centred, not pushed to the edge")
  func centresEvenWhenOversized() throws {
    let usable = CGRect(x: 0, y: 0, width: 1512, height: 944)
    let placed = try #require(
      OverlayGrid.placement(for: CGSize(width: 1600, height: 400), in: usable))

    #expect(placed.minX == -44)
    #expect(placed.midX == usable.midX)
  }

  @Test("An unknown screen places nothing, leaving the fallback to the caller")
  func reportsNothingForAnUnknownScreen() {
    #expect(OverlayGrid.placement(for: CGSize(width: 100, height: 100), in: .zero) == nil)
  }

  @Test("A panel with no size places nothing")
  func reportsNothingForAnEmptySize() {
    #expect(OverlayGrid.placement(for: .zero, in: Self.external) == nil)
  }

  /// Filling the screen is one division, not a search: a row of Spaces, their gaps
  /// and the surface's padding all scale with the tile, so the tile can be solved
  /// for. Wider screen, larger tile — and never past the range a thumbnail stays
  /// useful in.
  @Test("A tile grows into the screen it is given")
  func tileFillsTheScreen() {
    let narrow = TileMetrics.filling(width: 1200, columns: 5)
    let wide = TileMetrics.filling(width: 2400, columns: 5)

    #expect(narrow.width < wide.width)
    #expect(TileMetrics.range.contains(narrow.width))
    #expect(TileMetrics.range.contains(wide.width))
  }

  @Test("Every measurement follows the tile")
  func measurementsScaleWithTheTile() {
    let large = TileMetrics(width: 300)

    #expect(large.spacing > TileMetrics.base.spacing)
    #expect(large.thumbnailHeight > TileMetrics.base.thumbnailHeight)
    #expect(large.contentWidth == 300 - large.padding * 2)
  }

  /// Without bands the Spaces are one sequence: nine of them under a row of four
  /// are four, four and one, whichever display each belongs to.
  @Test("A flowing map ignores where a Space lives")
  func flowIgnoresDisplays() {
    let displays: [CGDirectDisplayID] = [1, 1, 1, 1, 1, 1, 2, 2, 2]

    #expect(
      OverlayGrid.spaceRows(ofDisplays: displays, perRow: 4, banded: false) == [
        [0, 1, 2, 3], [4, 5, 6, 7], [8],
      ]
    )
  }
}

/// Jumping to a window by the letter its name starts with.
extension OverlayGridTests {
  @Test("A letter jumps to the window of that name")
  func jumpsToTheMatchingApplication() {
    let tiles = [
      makeTile(id: 1, appName: "Arc"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(
      OverlayGrid.index(
        from: 0, matching: "c", in: tiles.map(OverlayTarget.window), field: .applicationName) == 1)
    #expect(
      OverlayGrid.index(
        from: 0, matching: "s", in: tiles.map(OverlayTarget.window), field: .applicationName) == 2)
  }

  @Test("The same letter again moves on to the next window of that name")
  func repeatedLetterCycles() {
    let tiles = [
      makeTile(id: 1, appName: "Claude"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(
      OverlayGrid.index(
        from: 0, matching: "c", in: tiles.map(OverlayTarget.window), field: .applicationName) == 1)
    #expect(
      OverlayGrid.index(
        from: 1, matching: "c", in: tiles.map(OverlayTarget.window), field: .applicationName) == 0)
  }

  @Test("Case does not matter, in the key or in the name")
  func matchingIgnoresCase() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "code")]

    #expect(
      OverlayGrid.index(
        from: 0, matching: "C", in: tiles.map(OverlayTarget.window), field: .applicationName) == 1)
  }

  @Test("The only window of that name keeps the highlight where it is")
  func aSingleMatchStaysPut() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(
      OverlayGrid.index(
        from: 1, matching: "c", in: tiles.map(OverlayTarget.window), field: .applicationName) == 1)
  }

  @Test("A letter nothing starts with matches nothing at all")
  func noMatchIsReportedAsSuch() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    // Not the current index: the caller has to tell "no window of that name" from
    // "the only one is already here", so that another reading of the key can run.
    #expect(
      OverlayGrid.index(
        from: 1, matching: "z", in: tiles.map(OverlayTarget.window), field: .applicationName) == nil
    )
    #expect(
      OverlayGrid.index(
        from: 0, matching: "z", in: [] as [OverlayTarget], field: .applicationName) == nil)
  }

  @Test("A letter can be matched against the window titles instead")
  func matchesAgainstTheWindowTitle() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Downloads"),
      makeTile(id: 2, appName: "Finder", title: "Черновик"),
      makeTile(id: 3, appName: "Finder", title: "Documents"),
    ]

    // The search still starts after the current tile.
    #expect(
      OverlayGrid.index(
        from: 0, matching: "d", in: tiles.map(OverlayTarget.window), field: .windowTitle) == 2)
    #expect(
      OverlayGrid.index(
        from: 2, matching: "d", in: tiles.map(OverlayTarget.window), field: .windowTitle) == 0)
    #expect(
      OverlayGrid.index(
        from: 0, matching: "ч", in: tiles.map(OverlayTarget.window), field: .windowTitle) == 1)
  }

  /// The list a letter walks, in drawing order, so the caller can rank the passes
  /// and still cycle through what it found.
  @Test("A letter reports every place it names")
  func reportsEveryMatch() {
    let targets = [
      makeTile(id: 1, appName: "Code", title: "example.md"),
      makeTile(id: 2, appName: "Claude", title: "Claude"),
      makeTile(id: 3, appName: "Arc", title: "Charts"),
    ].map(OverlayTarget.window)

    #expect(OverlayGrid.matches(for: "c", in: targets, field: .applicationName) == [0, 1])
    #expect(OverlayGrid.matches(for: "c", in: targets, field: .windowTitle) == [1, 2])
    #expect(OverlayGrid.matches(for: "e", in: targets, field: .windowTitle) == [0])
    #expect(OverlayGrid.matches(for: "z", in: targets, field: .applicationName).isEmpty)
  }

  /// A name is often two words and only one of them is the one anybody says:
  /// "Microsoft Excel" is Excel, and nobody presses "m" for it.
  @Test("A letter can start any word of a name, not only the first")
  func matchesTheStartOfAnyWord() {
    let targets = [
      makeTile(id: 1, appName: "Arc"),
      makeTile(id: 2, appName: "Microsoft Excel"),
    ].map(OverlayTarget.window)

    #expect(
      OverlayGrid.index(from: 0, matching: "e", in: targets, field: .applicationName) == nil,
      "the whole name does not start with it")
    #expect(
      OverlayGrid.index(
        from: 0, matching: "e", in: targets, field: .applicationName, scope: .anyWord) == 1)
  }

  /// Punctuation ends a word as surely as a space: a title like "Project — report"
  /// has a word starting with r.
  @Test("Punctuation ends a word too")
  func readsWordsAcrossPunctuation() {
    let targets = [makeTile(id: 1, appName: "Code", title: "Project — report.md")]
      .map(OverlayTarget.window)

    #expect(
      OverlayGrid.index(from: -1, matching: "r", in: targets, field: .windowTitle, scope: .anyWord)
        == 0)
    #expect(
      OverlayGrid.index(from: -1, matching: "m", in: targets, field: .windowTitle, scope: .anyWord)
        == 0)
  }

  /// The highlight counts empty Spaces as places it can sit, so a letter has to
  /// count them too. Matched against the windows alone, the number it returned
  /// meant the tile beside the one it named — one empty desktop earlier on the map
  /// was enough.
  @Test("A letter counts the empty Spaces the highlight can sit on")
  func matchingCountsEmptySpaces() {
    let targets: [OverlayTarget] = [
      .space(SpaceSectionID(displayID: 1, spaceIndex: 0)),
      .window(makeTile(id: 1, appName: "Arc")),
      .window(makeTile(id: 2, appName: "Telegram")),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "t", in: targets, field: .applicationName) == 2)
    #expect(OverlayGrid.index(from: 0, matching: "a", in: targets, field: .applicationName) == 1)
  }

  @Test("The two fields are searched separately, so a caller can rank them")
  func fieldsAreSearchedSeparately() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Code review"),
      makeTile(id: 2, appName: "Code", title: "Something"),
    ]

    #expect(
      OverlayGrid.index(
        from: 0, matching: "c", in: tiles.map(OverlayTarget.window), field: .applicationName) == 1)
    #expect(
      OverlayGrid.index(
        from: 1, matching: "c", in: tiles.map(OverlayTarget.window), field: .windowTitle) == 0)
  }
}

@Suite("What a window count does to the map's measurements")
struct MapShapeTests {
  /// The layout is measured again whenever the map's shape changes, and that costs
  /// a tenth of a second — so the shape has to describe what actually moves the
  /// measurements. A deck is drawn at one tile's size whatever it holds; only the
  /// badge beside the heading grows, and only when the digits do.
  @Test("Counts that draw the same badge share a shape")
  func foldsCountsThatDrawAlike() {
    #expect(OverlayWindowController.shape(of: 2) == OverlayWindowController.shape(of: 9))
    #expect(OverlayWindowController.shape(of: 10) == OverlayWindowController.shape(of: 99))
  }

  /// The three that do differ: nothing at all, one window without a badge, and a
  /// badge that has gained a digit.
  @Test("Nothing, one, and a wider badge are different shapes")
  func keepsCountsThatDrawDifferently() {
    let shapes = [0, 1, 2, 10, 100].map(OverlayWindowController.shape(of:))

    #expect(Set(shapes).count == shapes.count)
  }

  /// The label box is solved from the text it holds, not from the tile: the two
  /// grow at different rates, and a box measured in tiles was too small for its own
  /// two lines everywhere below a 400 point tile — which is where the second line
  /// went over the bottom edge of the card.
  @Test("Two lines fit under a thumbnail at every tile size")
  func labelsFitTheirBox() {
    for width in stride(from: 150.0, through: 560.0, by: 10.0) {
      let metrics = TileMetrics(width: width)
      let lines = (metrics.nameFontSize + metrics.titleFontSize) * 1.2

      #expect(metrics.labelHeight >= lines)
      #expect(metrics.thumbnailHeight > 0)
    }
  }
}
