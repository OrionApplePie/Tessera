import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("WindowSearch")
struct WindowSearchTests {
  private let candidates = [
    WindowSearch.Candidate(
      index: 0, application: "", title: "", place: "VG27AQL1A · Desktop 3"),
    WindowSearch.Candidate(
      index: 1, application: "Arc", title: "Telemetry settings", place: "Built-in · Desktop 1"),
    WindowSearch.Candidate(
      index: 2, application: "Telegram", title: "Alexander", place: "Built-in · Desktop 1"),
    WindowSearch.Candidate(
      index: 3, application: "TextEdit", title: "Привет.txt", place: "Built-in · Desktop 2"),
  ]

  /// The whole reason for weighting: "tel" is in an Arc window's title as well, and
  /// the application named Telegram is what was meant.
  @Test("An application's name outranks a window's title")
  func prefersTheApplicationName() {
    #expect(WindowSearch.best(for: ["tel"], among: candidates, after: 0) == 2)
  }

  /// A single letter has several equals, and pressing it again should move on
  /// rather than land on the same window.
  @Test("A letter walks the windows it names")
  func aLetterCyclesItsWindows() {
    let first = WindowSearch.best(for: ["t"], among: candidates, after: 0)

    #expect(first == 2)
    #expect(WindowSearch.best(for: ["t"], among: candidates, after: 2) == 3)
    #expect(WindowSearch.best(for: ["t"], among: candidates, after: 3) == 2, "and wraps around")
  }

  /// An empty Space has no window to be named by, so its heading is what finds it.
  @Test("A Space with nothing on it is found by its heading")
  func findsAnEmptySpaceByItsHeading() {
    #expect(WindowSearch.best(for: ["vg27"], among: candidates, after: 0) == 0)
    #expect(WindowSearch.best(for: ["desktop 3"], among: candidates, after: 0) == 0)
  }

  /// The same keys read two ways: what the Russian layout produced, and the Latin
  /// letters of those keys. Either may be the one that names the window.
  @Test("The readings of a key press are all tried")
  func triesEveryReading() {
    #expect(WindowSearch.best(for: ["еуд", "tel"], among: candidates, after: 0) == 2)
    #expect(WindowSearch.best(for: ["привет", "ghbdtn"], among: candidates, after: 0) == 3)
  }

  @Test("What nothing carries is reported as no match")
  func reportsNoMatch() {
    #expect(WindowSearch.best(for: ["zzz"], among: candidates, after: 0) == nil)
    #expect(WindowSearch.best(for: [""], among: candidates, after: 0) == nil)
  }

  /// The candidates are the places the highlight can sit on, in drawing order —
  /// including the Spaces with nothing on them, which the highlight counts too.
  @Test("Every place on the map is a candidate, empty Spaces included")
  func buildsCandidatesFromTheMap() {
    var empty = WindowTileSection(
      id: WindowSectionID(displayID: 1, spaceIndex: 0), title: "Desktop 1", tiles: [])
    empty.tiles = []

    let sections = [
      empty,
      WindowTileSection(
        id: WindowSectionID(displayID: 1, spaceIndex: 1),
        title: "Desktop 2",
        tiles: [makeTile(id: 1, appName: "Arc", title: "Home")]
      ),
    ]

    let built = WindowSearch.candidates(in: sections)

    #expect(built.map(\.index) == [0, 1])
    #expect(built[0].place == "Desktop 1")
    #expect(built[0].application.isEmpty)
    #expect(built[1].application == "Arc")
    #expect(built[1].title == "Home")
  }

  private func makeTile(id: CGWindowID, appName: String, title: String) -> WindowTileModel {
    WindowTileModel(
      id: id,
      appName: appName,
      title: title,
      processID: 1,
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
