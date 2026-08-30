import CoreGraphics
import Foundation
import Testing

@testable import Tessera

@Suite("Models")
struct ModelsTests {
  @Test("A tile with an app name and a title shows both verbatim")
  func showsNamesVerbatim() {
    let tile = makeTile(appName: "Safari", title: "Apple")

    #expect(tile.displayAppName == "Safari")
    #expect(tile.displayTitle == "Apple")
  }

  @Test("An empty app name falls back to a placeholder rather than an empty tile")
  func fallsBackForEmptyAppName() {
    let tile = makeTile(appName: "", title: "Apple")

    #expect(tile.displayAppName == "Unknown")
  }

  @Test("An empty title falls back to a placeholder rather than an empty tile")
  func fallsBackForEmptyTitle() {
    let tile = makeTile(appName: "Safari", title: "")

    #expect(tile.displayTitle == "<untitled>")
  }

  @Test("Windows are distinguished by their CoreGraphics window id")
  func windowIdentityIsTheWindowID() {
    let first = makeWindow(id: 11)
    let second = makeWindow(id: 12)
    let duplicate = makeWindow(id: 11)

    #expect(first == duplicate)
    #expect(first != second)
    #expect(Set([first, second, duplicate]).count == 2)
  }

  private func makeTile(appName: String, title: String) -> WindowTileModel {
    WindowTileModel(
      id: 1,
      appName: appName,
      title: title,
      processID: 100,
      isActive: false,
      isMinimized: false,
      displayID: 1,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }

  private func makeWindow(id: CGWindowID) -> WindowInfo {
    WindowInfo(
      id: id,
      appName: "Safari",
      title: "Apple",
      processID: 100,
      frame: CGRect(x: 0, y: 0, width: 800, height: 600),
      isOnScreen: true,
      isMinimized: false,
      displayID: 1
    )
  }
}

@Suite("WindowTileSection")
struct WindowTileSectionTests {
  @Test("Tiles are split where the display changes")
  func splitsOnDisplayChange() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1),
        makeTile(id: 2, displayID: 1),
        makeTile(id: 3, displayID: 2),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"]
    )

    #expect(sections.map(\.id.displayID) == [1, 2])
    #expect(sections.map(\.title) == ["Color LCD", "VG27AQL1A"])
    #expect(sections.map { $0.tiles.count } == [2, 1])
  }

  @Test("Tiles are split where the Space changes")
  func splitsOnSpaceChange() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 1, spaceIndex: 1),
      ],
      displayNames: [1: "Color LCD"],
      grouping: [.displays, .spaces]
    )

    #expect(sections.map(\.title) == ["Space 1", "Space 2"])
  }

  @Test("A display contributing one group is named without a Space")
  func doesNotNameASpaceWhenThereIsOnlyOneGroup() {
    // Two Spaces are known on this display, but only one has windows on show.
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 1),
        makeTile(id: 2, displayID: 2, spaceIndex: 0),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"],
      grouping: [.displays, .spaces]
    )

    #expect(sections.map(\.title) == ["Color LCD", "VG27AQL1A"])
  }

  @Test("Display and Space are both named when both distinguish the section")
  func namesDisplayAndSpaceTogether() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 2, spaceIndex: 0),
        makeTile(id: 3, displayID: 2, spaceIndex: 1),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"],
      grouping: [.displays, .spaces]
    )

    #expect(
      sections.map(\.title) == ["Color LCD", "VG27AQL1A · Space 1", "VG27AQL1A · Space 2"])
  }

  @Test("Windows on a Space nobody has visited are named as such")
  func namesTheUnknownSpace() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 1, spaceIndex: nil),
      ],
      displayNames: [1: "Color LCD"],
      grouping: [.displays, .spaces]
    )

    #expect(sections.map(\.title) == ["Space 1", "Other Spaces"])
  }

  @Test("One display and one Space need no heading at all")
  func saysNothingWhenThereIsNothingToSay() {
    let sections = WindowTileSection.sections(
      from: [makeTile(id: 1, displayID: 1, spaceIndex: 0)],
      displayNames: [1: "Color LCD"],
      grouping: [.displays, .spaces]
    )

    #expect(sections.map(\.title) == [""])
  }

  @Test("A display with no windows gets no section, even though it is connected")
  func aDisplayWithoutWindowsGetsNoSection() {
    let sections = WindowTileSection.sections(
      from: [makeTile(id: 1, displayID: 1)],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"]
    )

    #expect(sections.map(\.id.displayID) == [1])
  }

  @Test("Grouping by display alone leaves a display's Spaces together")
  func displayGroupingIgnoresSpaces() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 1, spaceIndex: 1),
        makeTile(id: 3, displayID: 2, spaceIndex: 0),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"],
      grouping: .displays
    )

    #expect(sections.map(\.title) == ["Color LCD", "VG27AQL1A"])
    #expect(sections.map { $0.tiles.count } == [2, 1])
  }

  @Test("Grouping by Space alone splits the Spaces but names no display")
  func spaceGroupingNamesNoDisplay() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 1, spaceIndex: 1),
      ],
      displayNames: [1: "Color LCD"],
      grouping: .spaces
    )

    #expect(sections.map(\.title) == ["Space 1", "Space 2"])
  }

  @Test("Without grouping every window lands in one untitled section")
  func flatGroupingYieldsOneSection() {
    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 2, spaceIndex: 1),
        makeTile(id: 3, displayID: 2, spaceIndex: nil),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"],
      grouping: []
    )

    #expect(sections.count == 1)
    #expect(sections.first?.title.isEmpty == true)
    #expect(sections.first?.tiles.map(\.id) == [1, 2, 3])
  }

  @Test("Without grouping and without tiles there is still nothing to draw")
  func flatGroupingWithoutTilesYieldsNothing() {
    #expect(
      WindowTileSection.sections(from: [], displayNames: [:], grouping: []).isEmpty)
  }

  @Test("No tiles yield no sections")
  func noTilesYieldNoSections() {
    #expect(
      WindowTileSection.sections(from: [], displayNames: [:]).isEmpty)
  }

  @Test("A display with no name falls back to its number")
  func fallsBackToTheDisplayNumber() {
    let sections = WindowTileSection.sections(
      from: [makeTile(id: 1, displayID: 7), makeTile(id: 2, displayID: 8)],
      displayNames: [:]
    )

    #expect(sections.first?.title == "Display 7")
  }

  @Test("Every tile survives the split")
  func keepsEveryTile() {
    let tiles = (1...5).map { makeTile(id: CGWindowID($0), displayID: $0 <= 2 ? 1 : 2) }

    let sections = WindowTileSection.sections(from: tiles, displayNames: [:])

    #expect(sections.flatMap(\.tiles).map(\.id) == tiles.map(\.id))
  }

  private func makeTile(
    id: CGWindowID,
    displayID: CGDirectDisplayID,
    spaceIndex: Int? = nil
  ) -> WindowTileModel {
    WindowTileModel(
      id: id,
      appName: "Finder",
      title: "Downloads",
      processID: 100,
      isActive: false,
      isMinimized: false,
      displayID: displayID,
      spaceIndex: spaceIndex,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }
}

@Suite("Arranging tiles")
struct WindowTileSectionSwapTests {
  private let sections = [
    WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: nil),
      title: "Color LCD",
      tiles: [makeTile(id: 1), makeTile(id: 2), makeTile(id: 3)]
    ),
    WindowTileSection(
      id: WindowSectionID(displayID: 2, spaceIndex: nil),
      title: "VG27AQL1A",
      tiles: [makeTile(id: 4), makeTile(id: 5)]
    ),
  ]

  @Test("Two tiles of one group change places")
  func swapsWithinASection() throws {
    let swapped = try #require(WindowTileSection.swapping(0, 2, in: sections))

    #expect(swapped[0].tiles.map(\.id) == [3, 2, 1])
    #expect(swapped[1].tiles.map(\.id) == [4, 5])
  }

  @Test("A swap is addressed by place in the whole list, not within a group")
  func addressesTilesByTheirFlatPlace() throws {
    let swapped = try #require(WindowTileSection.swapping(3, 4, in: sections))

    #expect(swapped[1].tiles.map(\.id) == [5, 4])
    #expect(swapped[0].tiles.map(\.id) == [1, 2, 3])
  }

  @Test("A swap across groups is refused, not silently relocated")
  func refusesToCrossASection() {
    #expect(WindowTileSection.swapping(2, 3, in: sections) == nil)
    #expect(WindowTileSection.swapping(0, 4, in: sections) == nil)
  }

  @Test("A tile does not swap with itself")
  func refusesToSwapATileWithItself() {
    #expect(WindowTileSection.swapping(1, 1, in: sections) == nil)
  }

  @Test("A place nobody occupies is refused")
  func refusesPlacesOutsideTheList() {
    #expect(WindowTileSection.swapping(0, 99, in: sections) == nil)
    #expect(WindowTileSection.swapping(0, 1, in: []) == nil)
  }

  private static func makeTile(id: CGWindowID) -> WindowTileModel {
    WindowTileModel(
      id: id,
      appName: "Finder",
      title: "Downloads",
      processID: 100,
      isActive: false,
      isMinimized: false,
      displayID: 1,
      spaceIndex: nil,
      icon: nil,
      thumbnail: nil,
      isThumbnailStale: false
    )
  }
}
