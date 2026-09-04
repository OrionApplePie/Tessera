import AppKit

/// The overlay as something you hold rather than something you open.
extension OverlayWindowController {

  /// ⌃⌥ with an arrow: opens the map if it is not up, and moves the highlight.
  ///
  /// Only the highlight moves. Nothing is raised and no Space is shown on the way,
  /// so the screen stays still while the choice is being made and the panel stays
  /// on the display it opened on — a map that switched Spaces under a hand still
  /// choosing was answering a question nobody had finished asking.
  func moveWhileHeld(_ direction: OverlayGrid.Direction) {
    if !isOverlayVisible {
      showOverlay()
    }

    moveSelection(direction)
  }

  /// The modifiers were let go: what the highlight is on is what was meant, so it
  /// is switched to and the overlay goes away. One change of screen, at the end.
  func switchOnRelease() {
    guard isOverlayVisible else {
      return
    }

    activateSelection()
  }
}
