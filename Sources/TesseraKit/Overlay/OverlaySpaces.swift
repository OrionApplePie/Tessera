import CoreGraphics
import Foundation

// MARK: - Spaces

/// Adding and closing desktops from the map.
///
/// Both go through Mission Control, which takes the whole screen while it is open,
/// so the map is put away first: left up, it would be drawn over the very buttons
/// being pressed. The list is refreshed afterwards, because a display that has
/// gained or lost a Space is a different map.
extension OverlayWindowController {
  /// Adds a desktop to the display the highlight is on.
  func addDesktop() {
    guard let displayID = selectedDisplay() else {
      logger.info("Nothing to add a desktop to: the highlight is on nothing")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      hideOverlay()

      guard await windowCoordinator.addDesktop(on: displayID) else {
        logger.info("Could not add a desktop to display \(displayID)")
        return
      }

      await windowCoordinator.refreshNow(force: true)
    }
  }

  /// Closes the Space the highlight is on.
  ///
  /// Only an empty one. A Space with windows on it closes just as readily — macOS
  /// moves them to the neighbouring Space — but that is a large thing to happen
  /// from one keystroke, and the map cannot show it before it is done.
  func closeSelectedSpace() {
    guard let section = windowCoordinator.targets[safe: selection.index]?.space,
      let index = section.spaceIndex
    else {
      logger.info("Closing a Space needs the highlight on an empty Space")
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      hideOverlay()

      guard await windowCoordinator.closeSpace(at: index, on: section.displayID) else {
        logger.info("Could not close Space \(index) of display \(section.displayID)")
        return
      }

      await windowCoordinator.refreshNow(force: true)
    }
  }

  /// The display the highlight is on, whether it sits on a window or on an empty
  /// Space.
  private func selectedDisplay() -> CGDirectDisplayID? {
    switch windowCoordinator.targets[safe: selection.index] {
    case .window(let tile):
      return tile.displayID
    case .space(let section):
      return section.displayID
    case nil:
      return nil
    }
  }
}
