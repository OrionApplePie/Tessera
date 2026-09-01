import AppKit
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
  private typealias CopyManagedDisplaySpaces = @convention(c) (Int32) -> Unmanaged<CFArray>?

  /// SkyLight's own name for "every Space", as opposed to only the visible ones.
  private static let allSpaces: Int32 = 0x7

  private static let frameworkPath =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

  private let connectionID: Int32?
  private let copySpacesForWindows: CopySpacesForWindows?
  private let getActiveSpace: GetActiveSpace?
  private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces?
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
      self.copyManagedDisplaySpaces = nil

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
    self.copyManagedDisplaySpaces = Self.symbol(
      handle, "SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"
    )
    .map { unsafeBitCast($0, to: CopyManagedDisplaySpaces.self) }

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

  /// Every Space, in the order the system keeps them — which is the order they
  /// appear in Mission Control and the order the ⌃1…⌃N shortcuts count in.
  ///
  /// Sorting by identifier instead would be our own order and not the one anybody
  /// sees: measured on this machine, the display whose Spaces the system lists as
  /// 4351, 4313, 4516, 4555, 4556, 4506 sorts by identifier into a different
  /// sequence entirely.
  /// One Space as the window server describes it: its identifier and whether it is
  /// a fullscreen window's Space rather than a desktop. The server says so in the
  /// same answer — type 4 is fullscreen, 0 is a desktop — which is how Mission
  /// Control knows to name one after an application and number the other.
  struct Space: Equatable {
    let id: Int
    let isFullscreen: Bool
  }

  func orderedSpaces() -> [CGDirectDisplayID: [Space]] {
    guard let connectionID, let copyManagedDisplaySpaces,
      let displays = copyManagedDisplaySpaces(connectionID)?.takeRetainedValue()
        as? [[String: Any]]
    else {
      return [:]
    }

    let displayIDs = Self.displayIDsByUUID()
    var ordered: [CGDirectDisplayID: [Space]] = [:]

    for display in displays {
      guard let uuid = display["Display Identifier"] as? String,
        let displayID = displayIDs[uuid]
      else {
        continue
      }

      let spaces = display["Spaces"] as? [[String: Any]] ?? []
      ordered[displayID] = spaces.compactMap { space in
        guard let id = (space["ManagedSpaceID"] as? Int) ?? (space["id64"] as? Int) else {
          return nil
        }

        return Space(id: id, isFullscreen: (space["type"] as? Int) == 4)
      }
    }

    return ordered
  }

  /// The window server names displays by UUID; everything else here uses the
  /// display id. `CGDisplayCreateUUIDFromDisplayID` is the public bridge between
  /// them.
  private static func displayIDsByUUID() -> [String: CGDirectDisplayID] {
    var byUUID: [String: CGDirectDisplayID] = [:]

    for screen in NSScreen.screens {
      let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
      guard let displayID = number.map({ CGDirectDisplayID($0.uint32Value) }),
        let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
      else {
        continue
      }

      byUUID[CFUUIDCreateString(nil, uuid) as String] = displayID
    }

    return byUUID
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
