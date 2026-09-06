import CoreGraphics
import Testing

@testable import TesseraKit

/// Only the ordering policy is covered here. Enumeration itself goes through
/// `SCShareableContent`, which needs a real screen and the Screen Recording
/// permission, so it is exercised by `tessera windows` rather than by a test.
@Suite("WindowListService")
struct WindowListServiceTests {
  @Test("Windows on the current Space come before windows anywhere else")
  func currentSpaceComesFirst() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, appName: "Arc", isOnScreen: false),
        makeWindow(id: 2, appName: "Safari", isOnScreen: true),
        makeWindow(id: 3, appName: "Bitwarden", isOnScreen: false),
        makeWindow(id: 4, appName: "Finder", isOnScreen: true),
      ],
      displayOrder: [1, 2],
      limit: 10
    )

    #expect(ordered.map(\.id) == [4, 2, 1, 3])
  }

  @Test("Within a group windows sort by app, then title, then window id")
  func sortsByAppThenTitleThenID() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 30, appName: "Safari", title: "Apple"),
        makeWindow(id: 10, appName: "Finder", title: "Downloads"),
        makeWindow(id: 20, appName: "Safari", title: "Anthropic"),
        makeWindow(id: 5, appName: "Finder", title: "Downloads"),
      ],
      displayOrder: [1, 2],
      limit: 10
    )

    #expect(ordered.map(\.id) == [5, 10, 20, 30])
  }

  @Test("The limit applies after sorting, so it keeps the current Space")
  func limitKeepsTheCurrentSpace() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, appName: "Arc", isOnScreen: false),
        makeWindow(id: 2, appName: "Zed", isOnScreen: true),
        makeWindow(id: 3, appName: "Bitwarden", isOnScreen: false),
      ],
      displayOrder: [1, 2],
      limit: 2
    )

    #expect(ordered.map(\.id) == [2, 1])
  }

  @Test("A display's windows are kept together, in the order the displays are given")
  func groupsWindowsByDisplay() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, appName: "Safari", displayID: 2),
        makeWindow(id: 2, appName: "Arc", displayID: 1),
        makeWindow(id: 3, appName: "Arc", displayID: 2),
        makeWindow(id: 4, appName: "Safari", displayID: 1),
      ],
      displayOrder: [1, 2],
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 4, 3, 1])
    #expect(ordered.map(\.displayID) == [1, 1, 2, 2])
  }

  @Test("The display order decides which section comes first")
  func displayOrderDecidesTheSections() {
    let windows = [
      makeWindow(id: 1, displayID: 1),
      makeWindow(id: 2, displayID: 2),
    ]

    #expect(
      WindowListService.ordered(windows, displayOrder: [2, 1], limit: 10).map(\.id) == [2, 1])
  }

  @Test("A window on a display nobody listed sorts last rather than disappearing")
  func unknownDisplaysSortLast() {
    let ordered = WindowListService.ordered(
      [makeWindow(id: 1, displayID: 99), makeWindow(id: 2, displayID: 1)],
      displayOrder: [1],
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 1])
  }

  @Test("A Space's windows are kept together, in rank order")
  func groupsWindowsBySpace() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, appName: "Arc"),
        makeWindow(id: 2, appName: "Arc"),
        makeWindow(id: 3, appName: "Arc"),
      ],
      displayOrder: [1],
      spaceRanks: [1: 1, 2: -1, 3: 0],
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 3, 1])
  }

  @Test("A window on a Space nobody has visited sorts after the known ones")
  func unknownSpacesSortLast() {
    let ordered = WindowListService.ordered(
      [makeWindow(id: 1), makeWindow(id: 2)],
      displayOrder: [1],
      spaceRanks: [2: 0],
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 1])
  }

  @Test("Ordering by application ignores the title, so a tab switch moves nothing")
  func applicationOrderIgnoresTheTitle() {
    // Alphabetically the titles run the other way round from the window ids, so
    // the two orders cannot agree by accident.
    let windows = [
      makeWindow(id: 1, appName: "Safari", title: "Zebra"),
      makeWindow(id: 2, appName: "Safari", title: "Apple"),
    ]

    #expect(
      WindowListService.ordered(
        windows, displayOrder: [1], order: .application, limit: 10
      ).map(\.id) == [1, 2])

    // The same windows sorted by title come out the other way round.
    #expect(
      WindowListService.ordered(
        windows, displayOrder: [1], order: .title, limit: 10
      ).map(\.id) == [2, 1])
  }

  @Test("A stable order follows the places given, and nothing else")
  func stableOrderFollowsTheGivenPlaces() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, appName: "Arc", isOnScreen: true),
        makeWindow(id: 2, appName: "Safari", isOnScreen: false),
        makeWindow(id: 3, appName: "Finder", isOnScreen: false),
      ],
      displayOrder: [1],
      sequence: [2: 0, 3: 1, 1: 2],
      order: .stable,
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 3, 1])
  }

  @Test("A stable order still keeps a display's windows together")
  func stableOrderStillGroupsByDisplay() {
    let ordered = WindowListService.ordered(
      [
        makeWindow(id: 1, displayID: 2),
        makeWindow(id: 2, displayID: 1),
      ],
      displayOrder: [1, 2],
      sequence: [1: 0, 2: 1],
      order: .stable,
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 1])
  }

  @Test("A window with no place yet sorts last rather than first")
  func stableOrderPutsUnplacedWindowsLast() {
    let ordered = WindowListService.ordered(
      [makeWindow(id: 1), makeWindow(id: 2)],
      displayOrder: [1],
      sequence: [2: 0],
      order: .stable,
      limit: 10
    )

    #expect(ordered.map(\.id) == [2, 1])
  }

  @Test("A limit of zero or less yields nothing instead of trapping")
  func nonPositiveLimitYieldsNothing() {
    let windows = [makeWindow(id: 1), makeWindow(id: 2)]

    #expect(WindowListService.ordered(windows, displayOrder: [1], limit: 0).isEmpty)
    #expect(WindowListService.ordered(windows, displayOrder: [1], limit: -1).isEmpty)
  }

  @Test("A limit beyond the window count keeps every window")
  func limitBeyondCountKeepsEverything() {
    let windows = [makeWindow(id: 1), makeWindow(id: 2)]

    #expect(WindowListService.ordered(windows, displayOrder: [1], limit: 99).count == 2)
  }

  @Test("Ordering is stable across refreshes, whatever order windows arrive in")
  func orderingIsStable() {
    let windows = [
      makeWindow(id: 1, appName: "Arc", isOnScreen: false),
      makeWindow(id: 2, appName: "Safari", isOnScreen: true),
      makeWindow(id: 3, appName: "Arc", isOnScreen: true),
    ]

    let first = WindowListService.ordered(windows, displayOrder: [1], limit: 10)
    let second = WindowListService.ordered(windows.reversed(), displayOrder: [1], limit: 10)

    #expect(first.map(\.id) == second.map(\.id))
  }

  private func makeWindow(
    id: CGWindowID,
    appName: String = "Finder",
    title: String = "Downloads",
    isOnScreen: Bool = true,
    isMinimized: Bool = false,
    displayID: CGDirectDisplayID = 1
  ) -> DiscoveredWindow {
    DiscoveredWindow(
      id: id,
      appName: appName,
      title: title,
      processID: 100,
      frame: CGRect(x: 0, y: 0, width: 800, height: 600),
      isOnScreen: isOnScreen,
      isMinimized: isMinimized,
      displayID: displayID
    )
  }
}
