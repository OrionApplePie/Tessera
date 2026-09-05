import CoreGraphics
import Foundation

// MARK: - Spaces from the command line

/// The commands that make, unmake and fill Spaces.
///
/// Kept apart from `CLI` itself because they are a different subject: everything
/// here goes through Mission Control, needs Accessibility, and shows itself on the
/// screen for a moment — none of which is true of listing or focusing a window.
extension CLI {
  // MARK: - Moving a window between Spaces

  /// `move <window id> left|right` — sends a window to the desktop beside the one
  /// it is on, which is what `⌘⇧` and an arrow do in the overlay.
  ///
  /// Mission Control draws only the windows of the Space its display is showing, so
  /// this works on a window that is in front. From the overlay the Space is shown
  /// first; here, saying so is more honest than switching the screen under a script.
  @MainActor
  static func runMove(
    _ windowID: CGWindowID,
    _ direction: String,
    config: AppConfig
  ) async throws {
    guard direction == "left" || direction == "right" else {
      throw CLIError.invalidArguments("Unknown direction: \(direction). Use left or right")
    }

    let snapshot = try await WindowListService(config: config).snapshot()

    guard let window = snapshot.windows.first(where: { $0.id == windowID }) else {
      throw CLIError.commandFailed("No window with id \(windowID)")
    }

    let query = SpaceQuery(enabled: config.usesPrivateSpaceAPI, debugMode: config.debugMode)
    let ordered = query.orderedSpaces()[window.displayID] ?? []

    guard let space = query.spaces(of: [windowID])[windowID],
      let index = ordered.firstIndex(where: { $0.id == space })
    else {
      throw CLIError.commandFailed("Cannot tell which Space that window is on")
    }

    let fullscreen = Set(ordered.enumerated().filter(\.element.isFullscreen).map(\.offset))

    guard
      let target = WindowCoordinator.space(
        beside: index, of: ordered.count, skipping: fullscreen, forward: direction == "right")
    else {
      throw CLIError.commandFailed("That display has no desktop \(direction) of Space \(index)")
    }

    let moving = MissionControl.Window(
      id: windowID, title: window.title, appName: window.appName, displayID: window.displayID)

    guard
      await MissionControl(config: config)
        .move(moving, toSpaceAt: target, on: window.displayID)
    else {
      throw CLIError.commandFailed("\(moving.name) did not move to Space \(target)")
    }

    print("Moved \(moving.name) to Space \(target).")
  }

  // MARK: - Space commands

  /// `space list`, `space add` and `space close`, on the display in use — the one
  /// showing the active Space, which is where the overlay opens too.
  ///
  /// Adding and closing go through Mission Control, so both need Accessibility and
  /// both show it for about a second. Which Space is which is read from the window
  /// server, so all three need `use_private_space_api` on; without it there is no
  /// way to say what a display is showing, and guessing would close the wrong
  /// desktop.
  @MainActor
  static func runSpace(_ action: String, index: Int?, config: AppConfig) async throws {
    let query = SpaceQuery(enabled: config.usesPrivateSpaceAPI, debugMode: config.debugMode)

    guard let displayID = query.activeDisplay() else {
      throw CLIError.commandFailed(
        "Cannot tell which display is in use; space commands need use_private_space_api = true")
    }

    switch action {
    case "list":
      listSpaces(on: displayID, among: query)

    case "add":
      guard await MissionControl(config: config).addDesktop(on: displayID) else {
        throw CLIError.commandFailed("No desktop appeared on display \(displayID)")
      }

      print("Added a desktop to display \(displayID).")
      listSpaces(on: displayID, among: query)

    case "close":
      try await closeSpace(index, on: displayID, among: query, config: config)

    default:
      throw CLIError.invalidArguments(
        "Unknown action: \(action). Usage: tessera space list|add|close [index]")
    }
  }

  /// Closes one Space by its index, or the one the display is showing when no index
  /// is given.
  @MainActor
  static func closeSpace(
    _ index: Int?,
    on displayID: CGDirectDisplayID,
    among query: SpaceQuery,
    config: AppConfig
  ) async throws {
    guard let target = index ?? currentSpaceIndex(on: displayID, among: query) else {
      throw CLIError.commandFailed("Cannot tell which Space display \(displayID) is showing")
    }

    guard await MissionControl(config: config).closeSpace(at: target, on: displayID) else {
      throw CLIError.commandFailed("Space \(target) of display \(displayID) was not closed")
    }

    print("Closed Space \(target) of display \(displayID).")
  }

  /// One display's Spaces, in the order the window server keeps them — which is the
  /// order Mission Control shows them in, so these indexes are what `space close`
  /// takes.
  @MainActor
  static func listSpaces(on displayID: CGDirectDisplayID, among query: SpaceQuery) {
    let showing = query.currentSpaces()[displayID]

    for (index, space) in (query.orderedSpaces()[displayID] ?? []).enumerated() {
      let kind = space.isFullscreen ? "fullscreen" : "desktop"
      let mark = space.id == showing ? " <- showing" : ""

      print("\(index)  \(kind)  id \(space.id)\(mark)")
    }
  }

  /// Where the Space a display is showing sits in that display's list.
  @MainActor
  static func currentSpaceIndex(
    on displayID: CGDirectDisplayID,
    among query: SpaceQuery
  ) -> Int? {
    guard let current = query.currentSpaces()[displayID] else {
      return nil
    }

    return query.orderedSpaces()[displayID]?.firstIndex { $0.id == current }
  }

}
