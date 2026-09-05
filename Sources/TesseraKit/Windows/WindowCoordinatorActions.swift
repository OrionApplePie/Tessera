import CoreGraphics
import Foundation

/// What the overlay can do to a window besides switch to it: put it on another
/// display, put it in a half of the one it is on, or hand it to the application's
/// own fullscreen mode.
///
/// Each says whether it happened rather than whether it was asked for. None of
/// these are things an application has to agree to — a window may be fixed in size,
/// or refuse fullscreen — so the answer comes from reading the window back, and the
/// caller is expected to do something with a `false`.
extension WindowCoordinator {
  func publish(
    _ tiles: [WindowTileModel],
    displayNames: [CGDirectDisplayID: String]
  ) {
    let all = WindowTileSection.sections(
      from: AudioActivity(debugMode: config.debugMode).marking(tiles),
      displayNames: displayNames, grouping: config.overlayGrouping,
      spaceCounts: spaceCounts, displayOrder: displayOrder, currentSpaces: currentSpaces,
      spaceNames: spaceNames, fullscreenSpaces: fullscreenSpaces)

    let budgets = OverlayGrid.budgets(forSections: all, config: config, on: activeDisplay)

    let fitted = WindowTileSection.fitting(
      all, cellsByDisplay: budgets, stacked: config.overlayDeck == .stack)
    let signature = WindowTileSection.signature(of: fitted)

    // Assigned only when the drawing would differ. The list is rebuilt several times
    // a second and almost always comes out the same; publishing it anyway redrew
    // every tile, which is what made the overlay feel heavy under the hand.
    guard signature != drawnSignature else {
      return
    }

    drawnSignature = signature
    draw(fitted)
  }

  /// Whether anything at all is making a sound, which decides whether a media key
  /// would interrupt something the person cannot see.
  var isAnythingPlaying: Bool {
    !AudioActivity(debugMode: config.debugMode).playingApplications().isEmpty
  }

  /// Sends a window to another display. Says whether it went.
  func sendWindow(_ tile: WindowTileModel, toDisplay displayID: CGDirectDisplayID) -> Bool {
    activator.send(tile, toDisplay: displayID)
  }

  /// Puts a window in a part of its screen. Says whether it went.
  func placeWindow(_ tile: WindowTileModel, _ placement: WindowPlacement) -> Bool {
    activator.place(tile, placement)
  }

  /// Turns a window's fullscreen mode on or off.
  func toggleFullscreen(_ tile: WindowTileModel) -> Bool {
    activator.toggleFullscreen(tile)
  }

  /// Adds a desktop to a display. Says whether one appeared.
  func addDesktop(on displayID: CGDirectDisplayID) async -> Bool {
    await MissionControl(config: config).addDesktop(on: displayID)
  }

  /// Closes one Space of a display, by its index among that display's Spaces. Says
  /// whether it went.
  func closeSpace(at index: Int, on displayID: CGDirectDisplayID) async -> Bool {
    await MissionControl(config: config).closeSpace(at: index, on: displayID)
  }

  /// Moves a window to a Space, which may be on another display: measured, a window
  /// dragged onto another display's bar changes display and Space at once. Says
  /// whether it went.
  func moveWindow(_ tile: WindowTileModel, to section: WindowSectionID) async -> Bool {
    guard let index = section.spaceIndex else {
      return false
    }

    let window = MissionControl.Window(
      id: tile.id, title: tile.title, appName: tile.appName, displayID: tile.displayID)

    return await MissionControl(config: config)
      .move(window, toSpaceAt: index, on: section.displayID)
  }

  /// Which section of the map a highlight falls in, given how many targets each
  /// section holds.
  nonisolated static func section(ofTarget index: Int, in counts: [Int]) -> Int? {
    var start = 0

    for (position, count) in counts.enumerated() {
      if index >= start, index < start + count {
        return position
      }

      start += count
    }

    return nil
  }

  /// The section beside one, in the order the map draws them.
  ///
  /// Fullscreen Spaces are stepped over: a window dropped on one asks macOS for a
  /// split view, not a move. Nothing wraps round, so the ends of the map are ends.
  nonisolated static func section(
    beside position: Int,
    among sections: [WindowSectionID],
    fullscreen: Set<WindowSectionID>,
    forward: Bool
  ) -> Int? {
    let step = forward ? 1 : -1
    var next = position + step

    while next >= 0, next < sections.count {
      if !fullscreen.contains(sections[next]) {
        return next
      }

      next += step
    }

    return nil
  }

  /// The desktop next to one, on the same display, or nothing when there is none
  /// that way.
  func spaceBeside(
    _ index: Int,
    on displayID: CGDirectDisplayID,
    forward: Bool
  ) -> Int? {
    let fullscreen = Set(
      fullscreenSpaces.filter { $0.displayID == displayID }.compactMap(\.spaceIndex))

    return Self.space(
      beside: index, of: spaceCounts[displayID] ?? 0, skipping: fullscreen, forward: forward)
  }

  /// Which Space an arrow means, given how many a display has and which of them are
  /// fullscreen.
  ///
  /// Fullscreen Spaces are stepped over: dropping a window on one asks macOS for a
  /// split view, which is not what "the next desktop" means. Nothing wraps round
  /// either — at the last desktop the arrow does nothing, because a keystroke that
  /// quietly sends a window across every Space to the first one is not what it
  /// looked like it would do.
  nonisolated static func space(
    beside index: Int,
    of count: Int,
    skipping fullscreen: Set<Int>,
    forward: Bool
  ) -> Int? {
    let step = forward ? 1 : -1
    var next = index + step

    while next >= 0, next < count {
      if !fullscreen.contains(next) {
        return next
      }

      next += step
    }

    return nil
  }
}
