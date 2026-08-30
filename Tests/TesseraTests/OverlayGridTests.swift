import CoreGraphics
import Testing

@testable import Tessera

@Suite("OverlayGrid")
struct OverlayGridTests {
  @Test("A row holds up to six tiles and never fewer than one")
  func columnCountIsCappedAtSix() {
    #expect(OverlayGrid.columnCount(forSectionSizes: []) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [0]) == 1)
    #expect(OverlayGrid.columnCount(forSectionSizes: [3]) == 3)
    #expect(OverlayGrid.columnCount(forSectionSizes: [13]) == 6)
  }

  @Test("Every section shares the widest section's column count")
  func columnCountIsSharedAcrossSections() {
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 5]) == 5)
    #expect(OverlayGrid.columnCount(forSectionSizes: [2, 9]) == 6)
  }

  @Test("A section always starts a new row")
  func sectionsStartNewRows() {
    #expect(OverlayGrid.rows(forSectionSizes: [3, 2]) == [[0, 1, 2], [3, 4]])
  }

  @Test("A section longer than a row wraps")
  func longSectionsWrap() {
    #expect(
      OverlayGrid.rows(forSectionSizes: [8, 2]) == [[0, 1, 2, 3, 4, 5], [6, 7], [8, 9]]
    )
  }

  @Test("Empty sections take up no rows")
  func emptySectionsAreSkipped() {
    #expect(OverlayGrid.rows(forSectionSizes: [0, 2]) == [[0, 1]])
    #expect(OverlayGrid.rows(forSectionSizes: []).isEmpty)
  }

  @Test("The highlight starts on the first window that is not already frontmost")
  func initialIndexSkipsTheActiveWindow() {
    let tiles = [makeTile(id: 1, isActive: true), makeTile(id: 2), makeTile(id: 3)]

    #expect(OverlayGrid.initialIndex(for: tiles) == 1)
  }

  @Test("With every window frontmost the highlight falls back to the first tile")
  func initialIndexFallsBackToZero() {
    #expect(OverlayGrid.initialIndex(for: [makeTile(id: 1, isActive: true)]) == 0)
    #expect(OverlayGrid.initialIndex(for: []) == 0)
  }

  @Test("Left and right step through the tiles in reading order and wrap")
  func horizontalMovementWalksTheList() {
    let rows = OverlayGrid.rows(forSectionSizes: [13])

    #expect(OverlayGrid.index(from: 0, moving: .right, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 7, moving: .left, rows: rows) == 6)
    #expect(OverlayGrid.index(from: 12, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: 0, moving: .left, rows: rows) == 12)
  }

  @Test("Left and right cross a section boundary without noticing it")
  func horizontalMovementCrossesSections() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 2])

    #expect(OverlayGrid.index(from: 2, moving: .right, rows: rows) == 3)
    #expect(OverlayGrid.index(from: 3, moving: .left, rows: rows) == 2)
  }

  @Test("Up and down move a whole row")
  func verticalMovementMovesARow() {
    let rows = OverlayGrid.rows(forSectionSizes: [13])

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 7)
    #expect(OverlayGrid.index(from: 7, moving: .up, rows: rows) == 1)
  }

  @Test("Down from the last row of a section lands in the next section")
  func verticalMovementEntersTheNextSection() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3])

    #expect(OverlayGrid.index(from: 1, moving: .down, rows: rows) == 4)
    #expect(OverlayGrid.index(from: 4, moving: .up, rows: rows) == 1)
  }

  @Test("A shorter row keeps the highlight in its last column")
  func verticalMovementClampsToAShorterRow() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2])

    // Column 3 has nothing under it, so the highlight lands on the row's last tile.
    #expect(OverlayGrid.index(from: 3, moving: .down, rows: rows) == 5)
  }

  @Test("Coming back up returns to the column the highlight actually sits in")
  func verticalMovementHasNoColumnMemory() {
    let rows = OverlayGrid.rows(forSectionSizes: [4, 2])

    // Down from column 3 clamped to column 1, so up goes to column 1, not back to 3.
    #expect(OverlayGrid.index(from: 5, moving: .up, rows: rows) == 1)
  }

  @Test("The top and bottom rows do not wrap around")
  func verticalMovementStopsAtTheEdges() {
    let rows = OverlayGrid.rows(forSectionSizes: [3, 3])

    #expect(OverlayGrid.index(from: 1, moving: .up, rows: rows) == 1)
    #expect(OverlayGrid.index(from: 4, moving: .down, rows: rows) == 4)
  }

  @Test("An out-of-range starting index is brought back in bounds")
  func clampsAnOutOfRangeIndex() {
    let rows = OverlayGrid.rows(forSectionSizes: [3])

    #expect(OverlayGrid.index(from: 99, moving: .right, rows: rows) == 0)
    #expect(OverlayGrid.index(from: -4, moving: .right, rows: rows) == 1)
  }

  @Test("With no tiles every direction is a no-op")
  func emptyGridDoesNotMove() {
    for direction in [OverlayGrid.Direction.left, .right, .up, .down] {
      #expect(OverlayGrid.index(from: 0, moving: direction, rows: []) == 0)
    }
  }

  private func makeTile(id: CGWindowID, isActive: Bool = false) -> WindowTileModel {
    WindowTileModel(
      id: id,
      appName: "Finder",
      title: "Downloads",
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
