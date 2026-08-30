import Testing

@testable import Tessera

@Suite("OverlayGrouping")
struct OverlayGroupingTests {
  @Test("Each axis can be asked for on its own")
  func parsesASingleAxis() throws {
    #expect(try OverlayGrouping(parsing: "displays") == .displays)
    #expect(try OverlayGrouping(parsing: "spaces") == .spaces)
  }

  @Test("Both axes can be asked for together, in either order")
  func parsesBothAxes() throws {
    let both: OverlayGrouping = [.displays, .spaces]

    #expect(try OverlayGrouping(parsing: "displays+spaces") == both)
    #expect(try OverlayGrouping(parsing: "spaces+displays") == both)
    #expect(try OverlayGrouping(parsing: "displays, spaces") == both)
  }

  @Test("Turning grouping off can be said either way")
  func parsesBothSpellingsOfOff() throws {
    #expect(try OverlayGrouping(parsing: "none").isEmpty)
    #expect(try OverlayGrouping(parsing: "flat").isEmpty)
  }

  @Test("Singular and plural mean the same, and case does not matter")
  func toleratesSpellingAndCase() throws {
    #expect(try OverlayGrouping(parsing: "  DISPLAY ") == .displays)
    #expect(try OverlayGrouping(parsing: "Space") == .spaces)
  }

  @Test("A grouping spells itself the same way whichever spelling built it")
  func nameIsCanonical() throws {
    #expect(try OverlayGrouping(parsing: "spaces+display").name == "displays+spaces")
    #expect(try OverlayGrouping(parsing: "None").name == "none")
    #expect(OverlayGrouping.displays.name == "displays")
  }

  @Test("Off combined with an axis is a contradiction, not a grouping")
  func refusesOffCombinedWithAnAxis() {
    #expect(throws: OverlayGroupingError.unknown("none+spaces")) {
      try OverlayGrouping(parsing: "none+spaces")
    }
  }

  @Test("Anything else is refused rather than quietly ignored")
  func refusesAnythingElse() {
    #expect(throws: OverlayGroupingError.unknown("")) { try OverlayGrouping(parsing: "") }
    #expect(throws: OverlayGroupingError.unknown("+")) { try OverlayGrouping(parsing: "+") }
    #expect(throws: OverlayGroupingError.unknown("apps")) { try OverlayGrouping(parsing: "apps") }
    #expect(throws: OverlayGroupingError.unknown("apps")) {
      try OverlayGrouping(parsing: "displays+apps")
    }
  }

  @Test("Displays are grouped by default, Spaces are not")
  func defaultGroupsDisplaysOnly() {
    #expect(AppConfig.default.overlayGrouping == .displays)
  }
}
