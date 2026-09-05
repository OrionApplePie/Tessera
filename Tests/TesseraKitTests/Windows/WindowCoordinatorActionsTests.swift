import Testing

@testable import TesseraKit

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
