import Testing

@testable import TesseraKit

@Suite("Choosing a Space to send a window to")
struct WindowSectionStepTests {
  private let sections = [
    WindowSectionID(displayID: 1, spaceIndex: 0),
    WindowSectionID(displayID: 1, spaceIndex: 1),
    WindowSectionID(displayID: 2, spaceIndex: 0),
    WindowSectionID(displayID: 2, spaceIndex: 1),
  ]

  /// The destination walks the map as it is drawn, so it crosses from one display
  /// to the next the way the eye does.
  @Test("The destination walks on into the next display")
  func crossesDisplays() {
    let next = WindowCoordinator.section(
      beside: 1, among: sections, fullscreen: [], forward: true)

    #expect(next == 2)
  }

  /// A fullscreen Space is not a destination: a window dropped on one asks macOS
  /// for a split view, which is not what was meant.
  @Test("A fullscreen Space is stepped over")
  func stepsOverFullscreen() {
    let next = WindowCoordinator.section(
      beside: 0, among: sections, fullscreen: [sections[1], sections[2]], forward: true)

    #expect(next == 3)
  }

  @Test("The end of the map is an end")
  func refusesToWrap() {
    #expect(
      WindowCoordinator.section(beside: 3, among: sections, fullscreen: [], forward: true) == nil)
    #expect(
      WindowCoordinator.section(beside: 0, among: sections, fullscreen: [], forward: false) == nil)
  }

  /// Which group of the map the highlight is in, which is where a destination
  /// starts from.
  @Test("A highlight belongs to the section its index falls in")
  func findsTheSectionOfATarget() {
    #expect(WindowCoordinator.section(ofTarget: 0, in: [2, 3, 1]) == 0)
    #expect(WindowCoordinator.section(ofTarget: 2, in: [2, 3, 1]) == 1)
    #expect(WindowCoordinator.section(ofTarget: 5, in: [2, 3, 1]) == 2)
    #expect(WindowCoordinator.section(ofTarget: 6, in: [2, 3, 1]) == nil)
  }

  /// An empty map has no section to start from, and saying so beats picking one.
  @Test("Nothing to be in when the map is empty")
  func refusesOnAnEmptyMap() {
    #expect(WindowCoordinator.section(ofTarget: 0, in: []) == nil)
  }
}

@Suite("Stepping a window to the next desktop")
struct WindowCoordinatorActionsTests {
  /// Fullscreen Spaces are stepped over. Dropping a window on one asks macOS for a
  /// split view, which is not what "the next desktop" means.
  @Test("A fullscreen Space is stepped over, not landed on")
  func stepsOverFullscreen() {
    let next = WindowCoordinator.space(
      beside: 0, of: 4, skipping: [1, 2], forward: true)

    #expect(next == 3)
  }

  @Test("The desktop beside one is the next along")
  func findsTheNeighbour() {
    #expect(WindowCoordinator.space(beside: 0, of: 3, skipping: [], forward: true) == 1)
    #expect(WindowCoordinator.space(beside: 2, of: 3, skipping: [], forward: false) == 1)
  }

  /// Nothing wraps round: a keystroke that quietly sends a window across every
  /// Space to the first one is not what the arrow looked like it would do.
  @Test("The ends are ends, not a way round")
  func refusesToWrap() {
    #expect(WindowCoordinator.space(beside: 2, of: 3, skipping: [], forward: true) == nil)
    #expect(WindowCoordinator.space(beside: 0, of: 3, skipping: [], forward: false) == nil)
  }

  /// A display whose other Spaces are all fullscreen has nowhere to send a window,
  /// and says so rather than landing on one of them.
  @Test("Only fullscreen Spaces that way means nowhere to go")
  func refusesWhenOnlyFullscreenIsLeft() {
    #expect(WindowCoordinator.space(beside: 0, of: 3, skipping: [1, 2], forward: true) == nil)
  }

  @Test("A display with one Space has no neighbour either way")
  func refusesOnASingleSpace() {
    #expect(WindowCoordinator.space(beside: 0, of: 1, skipping: [], forward: true) == nil)
    #expect(WindowCoordinator.space(beside: 0, of: 1, skipping: [], forward: false) == nil)
  }
}
