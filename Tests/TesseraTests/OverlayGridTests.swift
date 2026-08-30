import CoreGraphics
import Testing

@testable import Tessera

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

  @Test("A narrower maximum wraps a section sooner")
  func maximumWrapsSectionsSooner() {
    #expect(
      OverlayGrid.rows(forSectionSizes: [5], maximum: 4) == [[0, 1, 2, 3], [4]])
    #expect(
      OverlayGrid.rows(forSectionSizes: [5], maximum: 2) == [[0, 1], [2, 3], [4]])
  }

  @Test("Every section shares the widest section's column count")
  func columnCountIsSharedAcrossSections() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 5], maximum: 6) == 5)
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 9], maximum: 6) == 6)
  }

  @Test("A section always starts a new row")
  func sectionsStartNewRows() {
    #expect(OverlayGrid.rows(forSectionSizes: [3, 2], maximum: 6) == [[0, 1, 2], [3, 4]])
  }

  @Test("A section longer than a row wraps")
  func longSectionsWrap() {
    #expect(
      OverlayGrid.rows(forSectionSizes: [8, 2], maximum: 6) == [
        [0, 1, 2, 3, 4, 5], [6, 7], [8, 9],
      ]
    )
  }

  @Test("Empty sections take up no rows")
  func emptySectionsAreSkipped() {
    #expect(OverlayGrid.rows(forSectionSizes: [0, 2], maximum: 6) == [[0, 1]])
    #expect(OverlayGrid.rows(forSectionSizes: [], maximum: 6).isEmpty)
  }

  @Test("The highlight starts on the window you are in")
  func initialIndexIsTheActiveWindow() {
    let tiles = [makeTile(id: 1), makeTile(id: 2, isActive: true), makeTile(id: 3)]

    #expect(OverlayGrid.initialIndex(for: tiles) == 1)
  }

  @Test("With no window frontmost the highlight falls back to the first tile")
  func initialIndexFallsBackToZero() {
    #expect(OverlayGrid.initialIndex(for: [makeTile(id: 1), makeTile(id: 2)]) == 0)
    #expect(OverlayGrid.initialIndex(for: []) == 0)
  }

  @Test("Left and right step through the tiles in reading order and wrap")
  func horizontalMovementWalksTheList() {
    let rows = OverlayGrid.rows(forSectionSizes: [13], maximum: 6)

    #expect(OverlayGrid.index(from: 0, moving: .right, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 7, moving: .left, rows: rows) == 6)
    #expect(OverlayGrid.index(from: 12, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, rows: rows) == 12)
  }

  @Test("Left and right cross a section boundary without noticing it")
  func horizontalMovementCrossesSections() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 2], maximum: 6)

    #expect(OverlayGrid.index(from: 2, moving: .right, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .left, rows: rows) == 2)
  }

  @Test("Up and down move a whole row")
  func verticalMovementMovesARow() {
    let rows = OverlayGrid.rows(forSectionSizes: [13], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 7)
    #expect(OverlayGrid.index(from: 7, moving: .up, rows: rows) == 1)
  }

  @Test("Down from the last row of a section lands in the next section")
  func verticalMovementEntersTheNextSection() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .up, rows: rows) == 1)
  }

  @Test("A shorter row keeps the highlight in its last column")
  func verticalMovementClampsToAShorterRow() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2], maximum: 6)

    // Column 3 has nothing under it, so the highlight lands on the row's last tile.
    #expect(OverlayGrid.index(from: 3, moving: .down, rows: rows) == 5)
  }

  @Test("Coming back up returns to the column the highlight actually sits in")
  func verticalMovementHasNoColumnMemory() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2], maximum: 6)

    // Down from column 3 clamped to column 1, so up goes to column 1, not back to 3.
    #expect(OverlayGrid.index(from: 5, moving: .up, rows: rows) == 1)
  }

  @Test("The top and bottom rows do not wrap around")
  func verticalMovementStopsAtTheEdges() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3], maximum: 6)

    #expect(OverlayGrid.index(from: 1, moving: .up, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 4, moving: .down, rows: rows) == 4)
  }

  @Test("An out-of-range starting index is brought back in bounds")
  func clampsAnOutOfRangeIndex() {
    let rows = OverlayGrid.rows(forSectionSizes: [3], maximum: 6)

    #expect(OverlayGrid.index(from: 99, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: -4, moving: .right, rows: rows) == 1)
  }

  @Test("With no tiles every direction is a no-op")
  func emptyGridDoesNotMove() {
    for direction in [OverlayGrid.Direction.left, .right, .up, .down] {
      #expect(OverlayGrid.index(from: 0, moving: direction, rows: []) == 0)
    }
  }

  @Test("A letter jumps to the window of that name")
  func jumpsToTheMatchingApplication() {
    let tiles = [
      makeTile(id: 1, appName: "Arc"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles) == 1)
    #expect(OverlayGrid.index(from: 0, matching: "s", in: tiles) == 2)
  }

  @Test("The same letter again moves on to the next window of that name")
  func repeatedLetterCycles() {
    let tiles = [
      makeTile(id: 1, appName: "Claude"),
      makeTile(id: 2, appName: "Code"),
      makeTile(id: 3, appName: "Safari"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles) == 1)
    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles) == 0)
  }

  @Test("Case does not matter, in the key or in the name")
  func matchingIgnoresCase() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "code")]

    #expect(OverlayGrid.index(from: 0, matching: "C", in: tiles) == 1)
  }

  @Test("The only window of that name keeps the highlight where it is")
  func aSingleMatchStaysPut() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles) == 1)
  }

  @Test("A letter nothing starts with matches nothing at all")
  func noMatchIsReportedAsSuch() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    // Not the current index: the caller has to tell "no window of that name" from
    // "the only one is already here", so that another reading of the key can run.
    #expect(OverlayGrid.index(from: 1, matching: "z", in: tiles) == nil)
    #expect(OverlayGrid.index(from: 0, matching: "z", in: [] as [WindowTileModel]) == nil)
  }

  @Test("With no application matching, the window titles get a turn")
  func fallsBackToTheWindowTitle() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Downloads"),
      makeTile(id: 2, appName: "Finder", title: "Тезисы"),
      makeTile(id: 3, appName: "Finder", title: "Documents"),
    ]

    // No application starts with "d", so the titles decide, and the search still
    // starts after the current tile.
    #expect(OverlayGrid.index(from: 0, matching: "d", in: tiles) == 2)
    #expect(OverlayGrid.index(from: 2, matching: "d", in: tiles) == 0)
    #expect(OverlayGrid.index(from: 0, matching: "т", in: tiles) == 1)
  }

  @Test("An application match wins over a title match")
  func applicationBeatsTitle() {
    let tiles = [
      makeTile(id: 1, appName: "Finder", title: "Code review"),
      makeTile(id: 2, appName: "Code", title: "Something"),
    ]

    #expect(OverlayGrid.index(from: 0, matching: "c", in: tiles) == 1)
    #expect(OverlayGrid.index(from: 1, matching: "c", in: tiles) == 1)
  }

  @Test("An out-of-range index does not stop a jump")
  func jumpClampsTheStartingIndex() {
    let tiles = [makeTile(id: 1, appName: "Arc"), makeTile(id: 2, appName: "Code")]

    #expect(OverlayGrid.index(from: 99, matching: "a", in: tiles) == 0)
  }

  private func makeTile(
    id: CGWindowID,
    isActive: Bool = false,
    appName: String = "Finder",
    title: String = "Downloads"
  ) -> WindowTileModel {
    WindowTileModel(
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
