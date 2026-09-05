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

  /// Choosing where to send the highlighted window: `⌘⇧` with the arrows walks a
  /// destination across the map, and letting the keys go sends the window there.
  ///
  /// Two keys rather than one, and nothing happens until they are released, because
  /// a Space has to be chosen first — the arrows would otherwise move a window one
  /// desktop at a time, through every desktop on the way, which is a different
  /// thing from putting it where you meant.
  func aimAtSpace(_ direction: OverlayGrid.Direction) {
    guard windowCoordinator.targets[safe: selection.index]?.window != nil else {
      logger.info("Nothing to send: the highlight is on a Space, not a window")
      return
    }

    let sections = windowCoordinator.sections.map(\.id)
    let counts = windowCoordinator.sections.map(\.targets.count)

    guard let home = WindowCoordinator.section(ofTarget: selection.index, in: counts) else {
      return
    }

    let from = selection.movingTo.flatMap { sections.firstIndex(of: $0) } ?? home

    guard
      let next = WindowCoordinator.section(
        beside: from,
        among: sections,
        fullscreen: windowCoordinator.fullscreenSpaces,
        forward: direction == .right || direction == .down)
    else {
      return
    }

    selection.movingTo = sections[next]
  }

  /// The keys were let go: the Space the destination is on is where the window goes.
  ///
  /// A destination that is the Space the window is already on is a choice made and
  /// unmade, so nothing happens and nothing is said.
  func commitMoveToSpace() {
    guard let section = selection.movingTo else {
      return
    }

    selection.movingTo = nil

    guard let tile = windowCoordinator.targets[safe: selection.index]?.window else {
      return
    }

    Task { @MainActor [weak self] in
      guard let self else {
        return
      }

      // Mission Control draws only the windows of the Space its display is showing,
      // so a window that is elsewhere is brought forward before it can be dragged.
      if let space = tile.spaceIndex, windowCoordinator.currentSpaces[tile.displayID] != space {
        await windowCoordinator.showSpace(at: space, on: tile.displayID, handingBack: false)
      }

      hideOverlay()

      guard await windowCoordinator.moveWindow(tile, to: section) else {
        logger.info("Could not send \(tile.displayAppName) to that Space")
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
