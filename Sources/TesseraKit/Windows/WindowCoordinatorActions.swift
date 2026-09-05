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
}
