import Testing

@testable import TesseraKit

/// Reading the state needs Accessibility and a real application, so what is
/// covered here is the lookup the rest of the app depends on.
@Suite("MinimizedWindows")
struct MinimizedWindowsTests {
  private let windows = MinimizedWindows(titlesByProcessID: [100: ["Downloads", "Documents"]])

  @Test("A window whose title was reported minimized is minimized")
  func findsAReportedWindow() {
    #expect(windows.contains(processID: 100, title: "Downloads"))
    #expect(windows.contains(processID: 100, title: "Documents"))
  }

  @Test("Another window of the same application is not")
  func doesNotMatchOtherWindows() {
    #expect(windows.contains(processID: 100, title: "Desktop") == false)
  }

  @Test("The same title in another application is not")
  func doesNotMatchAcrossProcesses() {
    #expect(windows.contains(processID: 200, title: "Downloads") == false)
  }

  @Test("An untitled window never matches, because there is nothing to match on")
  func neverMatchesAnUntitledWindow() {
    let untitled = MinimizedWindows(titlesByProcessID: [100: [""]])

    #expect(untitled.contains(processID: 100, title: "") == false)
    #expect(windows.contains(processID: 100, title: "") == false)
  }

  @Test("Knowing nothing means nothing is minimized")
  func emptyKnowledgeMinimizesNothing() {
    let empty = MinimizedWindows(titlesByProcessID: [:])

    #expect(empty.contains(processID: 100, title: "Downloads") == false)
  }
}
