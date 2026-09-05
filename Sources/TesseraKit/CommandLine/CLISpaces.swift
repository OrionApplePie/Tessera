import CoreGraphics
import Foundation

// MARK: - Spaces from the command line

/// The commands that make, unmake and fill Spaces.
///
/// Kept apart from `CLI` itself because they are a different subject: everything
/// here goes through Mission Control, needs Accessibility, and shows itself on the
/// screen for a moment — none of which is true of listing or focusing a window.
extension CLI {
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
