import CoreGraphics
import Foundation

/// Asks the window server which Space a window is on.
///
/// This is the one place in the project that uses a private interface, and it is
/// written so that losing it costs nothing but accuracy. SkyLight is opened by
/// path and every function is looked up by name at run time: a symbol Apple
/// renames or removes is a `nil` here, `isAvailable` turns false, and everything
/// falls back to `SpaceTracker`, which infers Space membership from what appears on
/// screen together. That fallback is the behaviour this project had before, so a
/// broken macOS update degrades the switcher rather than breaking it.
///
/// What it buys is exactness. Measured against two fullscreen VS Code windows: the
/// one on screen answers with the active Space, the other with a Space of its own,
/// which no public API will say and no amount of observing can prove.
@MainActor
final class SpaceQuery {
  private typealias MainConnectionID = @convention(c) () -> Int32
  private typealias CopySpacesForWindows =
    @convention(c) (Int32, Int32, CFArray) ->
    Unmanaged<CFArray>?
  private typealias GetActiveSpace = @convention(c) (Int32) -> UInt64

  /// SkyLight's own name for "every Space", as opposed to only the visible ones.
  private static let allSpaces: Int32 = 0x7

  private static let frameworkPath =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

  private let connectionID: Int32?
  private let copySpacesForWindows: CopySpacesForWindows?
  private let getActiveSpace: GetActiveSpace?
  private let logger: AppLogger

  var isAvailable: Bool {
    connectionID != nil && copySpacesForWindows != nil
  }

  init(enabled: Bool, debugMode: Bool) {
    self.logger = AppLogger(debugMode: debugMode, category: .preview)

    guard enabled, let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
      self.connectionID = nil
      self.copySpacesForWindows = nil
      self.getActiveSpace = nil

      if enabled {
        logger.warning("SkyLight did not open; Spaces will be inferred from what is on screen")
      }

      return
    }

    // Both spellings are tried: the functions were CGS before they were SLS, and
    // which one an OS exports has changed before.
    let connection = Self.symbol(handle, "SLSMainConnectionID", "CGSMainConnectionID")
      .map { unsafeBitCast($0, to: MainConnectionID.self) }
    let spaces = Self.symbol(handle, "SLSCopySpacesForWindows", "CGSCopySpacesForWindows")
      .map { unsafeBitCast($0, to: CopySpacesForWindows.self) }
    let active = Self.symbol(handle, "SLSGetActiveSpace", "CGSGetActiveSpace")
      .map { unsafeBitCast($0, to: GetActiveSpace.self) }

    self.connectionID = connection.map { $0() }
    self.copySpacesForWindows = spaces
    self.getActiveSpace = active

    if spaces == nil || connection == nil {
      logger.warning(
        "SkyLight is missing the calls this needs; Spaces will be inferred from what is on screen")
    }
  }

  /// The Space each window sits on, for the windows the window server will say.
  ///
  /// A window with no Space at all is left out rather than given one: that is what
  /// a window belonging to no Space looks like, and guessing would undo the point
  /// of asking.
  func spaces(of windowIDs: [CGWindowID]) -> [CGWindowID: Int] {
    guard let connectionID, let copySpacesForWindows else {
      return [:]
    }

    var found: [CGWindowID: Int] = [:]

    for windowID in windowIDs {
      let request = [NSNumber(value: windowID)] as CFArray
      guard
        let answer = copySpacesForWindows(connectionID, Self.allSpaces, request)?
          .takeRetainedValue() as? [Int],
        let space = answer.first
      else {
        continue
      }

      found[windowID] = space
    }

    return found
  }

  /// The Space showing now, which is what orders the groups: the one you are on
  /// comes first.
  func activeSpace() -> Int? {
    guard let connectionID, let getActiveSpace else {
      return nil
    }

    return Int(getActiveSpace(connectionID))
  }

  private static func symbol(
    _ handle: UnsafeMutableRawPointer,
    _ name: String,
    _ olderName: String
  ) -> UnsafeMutableRawPointer? {
    dlsym(handle, name) ?? dlsym(handle, olderName)
  }
}
