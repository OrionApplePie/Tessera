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

  /// Unplugging the external display moved its fullscreen Spaces onto the built-in,
  /// and with one display left there was nothing in the heading but the Space's own
  /// name — which a fullscreen Space declines to give. The group lost its heading,
  /// its frame and the tap that shows it.
  @Test("A fullscreen Space is named when nothing else names it")
  func namesAFullscreenSpaceWhenItIsAllThereIs() {
    let fullscreen = WindowSectionID(displayID: 1, spaceIndex: 1)

    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 1, spaceIndex: 1),
      ],
      displayNames: [1: "Color LCD"],
      grouping: [.displays, .spaces],
      spaceNames: [WindowSectionID(displayID: 1, spaceIndex: 0): "Desktop 1", fullscreen: ""],
      fullscreenSpaces: [fullscreen]
    )

    #expect(sections.map(\.title) == ["Desktop 1", "Fullscreen"])
  }

  /// With a display's name beside it the Space still says nothing: the mark and the
  /// tile under it already say which window is fullscreen, and naming the
  /// application there was the same word twice.
  @Test("A fullscreen Space beside another display keeps the display's name alone")
  func leavesAFullscreenSpaceUnnamedBesideADisplay() {
    let fullscreen = WindowSectionID(displayID: 2, spaceIndex: 0)

    let sections = WindowTileSection.sections(
      from: [
        makeTile(id: 1, displayID: 1, spaceIndex: 0),
        makeTile(id: 2, displayID: 2, spaceIndex: 0),
      ],
      displayNames: [1: "Color LCD", 2: "VG27AQL1A"],
      grouping: [.displays, .spaces],
      spaceNames: [fullscreen: ""],
      fullscreenSpaces: [fullscreen]
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
      tiles: [Self.makeTile(id: 1), Self.makeTile(id: 2), Self.makeTile(id: 3)]
    ),
    WindowTileSection(
      id: WindowSectionID(displayID: 2, spaceIndex: nil),
      title: "VG27AQL1A",
      tiles: [Self.makeTile(id: 4), Self.makeTile(id: 5)]
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

  /// Reported as "closed a window and the empty desktops disappeared": every group
  /// left without tiles was dropped, and an empty Space has no tiles by definition.
  @Test("Closing a window leaves the empty Spaces where they were")
  func closingAWindowKeepsEmptySpaces() {
    let empty = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 1), title: "Desktop 2", tiles: [])
    let occupied = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 0),
      title: "Desktop 1",
      tiles: [Self.makeTile(id: 7)]
    )

    let left = WindowTileSection.removing(7, from: [occupied, empty])

    #expect(left.count == 2)
    #expect(left.allSatisfy { $0.tiles.isEmpty })
  }

  /// A Space that has just lost its last window is an empty desktop, and stays on
  /// the map as one — the place did not go anywhere.
  @Test("A Space emptied by the close stays as a place")
  func closingTheLastWindowLeavesTheSpace() {
    let section = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 2),
      title: "Desktop 3",
      tiles: [Self.makeTile(id: 3)]
    )

    #expect(WindowTileSection.removing(3, from: [section]).count == 1)
  }

  /// A group standing for no Space at all is the exception: with its tiles gone
  /// there is nothing left for it to mean.
  @Test("A group of windows on no known Space goes when its last tile does")
  func closingTheLastWindowOfAnUnknownSpaceDropsTheGroup() {
    let section = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: nil),
      title: "Other",
      tiles: [Self.makeTile(id: 4)]
    )

    #expect(WindowTileSection.removing(4, from: [section]).isEmpty)
  }

  /// A cell is what stands beside its neighbour: one card for a stacked Space
  /// however many windows it holds, one for every window when they are fanned out.
  @Test("A Space costs one cell stacked and one per window fanned")
  func cellsCountWhatIsDrawn() {
    let section = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 0),
      title: "Desktop 1",
      tiles: [Self.makeTile(id: 1), Self.makeTile(id: 2), Self.makeTile(id: 3)]
    )

    #expect(section.cells(whenStacked: true) == 1)
    #expect(section.cells(whenStacked: false) == 3)
  }

  /// An empty Space is still a cell: it is drawn, so it takes room.
  @Test("An empty Space costs a cell either way")
  func anEmptySpaceCostsACell() {
    let empty = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 4), title: "Desktop 5", tiles: [])

    #expect(empty.cells(whenStacked: true) == 1)
    #expect(empty.cells(whenStacked: false) == 1)
  }

  /// The budget is per display, and what does not fit is left off the end — a map
  /// that keeps everything by making every tile too small to read answers the wrong
  /// question.
  @Test("The map is cut to its budget, display by display")
  func trimsToTheBudget() {
    let sections = (0..<6).map { index in
      WindowTileSection(
        id: WindowSectionID(displayID: index < 3 ? 1 : 2, spaceIndex: index),
        title: "Desktop \(index)",
        tiles: []
      )
    }

    let kept = WindowTileSection.fitting(sections, cellsPerDisplay: 2, stacked: true)

    #expect(kept.count == 4)
    #expect(kept.filter { $0.id.displayID == 1 }.count == 2)
  }

  /// The displays do not always want the same amount of map, so each gets a budget
  /// of its own rather than a share nobody measured.
  @Test("Each display is held to its own budget")
  func trimsToPerDisplayBudgets() {
    let sections = (0..<8).map { index in
      WindowTileSection(
        id: WindowSectionID(displayID: index < 4 ? 1 : 2, spaceIndex: index),
        title: "Desktop \(index)",
        tiles: []
      )
    }

    let kept = WindowTileSection.fitting(
      sections, cellsByDisplay: [1: 3, 2: 1], stacked: true)

    #expect(kept.filter { $0.id.displayID == 1 }.count == 3)
    #expect(kept.filter { $0.id.displayID == 2 }.count == 1)
  }

  /// A display with no budget at all draws nothing — the caller decides the shares,
  /// and a missing one is a share of none rather than a share of everything.
  @Test("A display the budget does not mention draws nothing")
  func dropsADisplayWithoutABudget() {
    let sections = [
      WindowTileSection(id: WindowSectionID(displayID: 1, spaceIndex: 0), title: "a", tiles: []),
      WindowTileSection(id: WindowSectionID(displayID: 2, spaceIndex: 1), title: "b", tiles: []),
    ]

    let kept = WindowTileSection.fitting(sections, cellsByDisplay: [1: 2], stacked: true)

    #expect(kept.map(\.id.displayID) == [1])
  }

  /// Kept as an extra, the Space you are on turned a band of five into a band of
  /// six — a second row on a map budgeted in rows. It is spent first instead.
  @Test("The Space you are on is charged to the budget, not added to it")
  func chargesTheCurrentSpaceToTheBudget() {
    var current = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 9), title: "Desktop 10", tiles: [])
    current.isCurrent = true

    let sections =
      (0..<5).map { (index: Int) in
        WindowTileSection(
          id: WindowSectionID(displayID: 1, spaceIndex: index), title: "\(index)", tiles: [])
      } + [current]

    let kept = WindowTileSection.fitting(sections, cellsByDisplay: [1: 5], stacked: true)

    #expect(kept.count == 5)
    #expect(kept.contains { $0.isCurrent })
  }

  /// The Space you are on is never cut: it is the one place the map has to show.
  @Test("The Space you are on survives the budget")
  func keepsTheCurrentSpace() {
    var last = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 9), title: "Desktop 10", tiles: [])
    last.isCurrent = true

    let sections =
      (0..<3).map { (index: Int) in
        WindowTileSection(
          id: WindowSectionID(displayID: 1, spaceIndex: index), title: "\(index)", tiles: [])
      } + [last]

    let kept = WindowTileSection.fitting(sections, cellsPerDisplay: 2, stacked: true)

    #expect(kept.contains { $0.isCurrent })
  }
}
