import CoreGraphics
import Testing

@testable import TesseraKit

@Suite("FrontmostWindow")
struct FrontmostWindowTests {
  /// Two windows of one application, and a third of another, front to back.
  private let frontToBack = [
    FrontmostWindow.Entry(windowID: 10, processID: 100),
    FrontmostWindow.Entry(windowID: 11, processID: 100),
    FrontmostWindow.Entry(windowID: 20, processID: 200),
  ]

  @Test("Only the window in front is frontmost, not every window of its application")
  func picksOneWindowOfAnApplication() {
    let identified = FrontmostWindow.identify(
      processID: 100,
      among: [10, 11, 20],
      frontToBack: frontToBack
    )

    #expect(identified == 10)
  }

  @Test("The order on screen decides, not the order the windows were listed in")
  func followsTheOrderOnScreen() {
    let reordered = [
      FrontmostWindow.Entry(windowID: 11, processID: 100),
      FrontmostWindow.Entry(windowID: 10, processID: 100),
    ]

    #expect(
      FrontmostWindow.identify(processID: 100, among: [10, 11], frontToBack: reordered) == 11)
  }

  @Test("A window the switcher does not list is skipped over")
  func skipsWindowsThatAreNotListed() {
    let identified = FrontmostWindow.identify(
      processID: 100,
      among: [11],
      frontToBack: frontToBack
    )

    #expect(identified == 11)
  }

  @Test("An application with nothing on screen is frontmost over nothing")
  func returnsNothingForAnApplicationWithoutWindows() {
    #expect(
      FrontmostWindow.identify(processID: 300, among: [10, 11], frontToBack: frontToBack) == nil)
    #expect(FrontmostWindow.identify(processID: 100, among: [], frontToBack: frontToBack) == nil)
    #expect(FrontmostWindow.identify(processID: 100, among: [10], frontToBack: []) == nil)
  }

  @Test("With no application in front there is no frontmost window")
  func returnsNothingWithoutAnApplication() {
    #expect(
      FrontmostWindow.identify(processID: nil, among: [10], frontToBack: frontToBack) == nil)
  }
}
