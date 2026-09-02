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
  private typealias SetCurrentSpace = @convention(c) (Int32, CFString, UInt64) -> Void

  /// SkyLight's own name for "every Space", as opposed to only the visible ones.
  private static let allSpaces: Int32 = 0x7

  private static let frameworkPath =
    "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"

  private let connectionID: Int32?
  private let copySpacesForWindows: CopySpacesForWindows?
  private let getActiveSpace: GetActiveSpace?
  private let copyManagedDisplaySpaces: CopyManagedDisplaySpaces?
  private let setCurrentSpace: SetCurrentSpace?
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
      self.setCurrentSpace = nil

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
    self.setCurrentSpace = Self.symbol(
      handle, "SLSManagedDisplaySetCurrentSpace", "CGSManagedDisplaySetCurrentSpace"
    )
    .map { unsafeBitCast($0, to: SetCurrentSpace.self) }

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

  /// The Space each display is showing. Every display shows one, and only one of
  /// them is "active" — so asking `SLSGetActiveSpace` marks a single group on a map
  /// that has a current Space per display.
  func currentSpaces() -> [CGDirectDisplayID: Int] {
    guard let connectionID, let copyManagedDisplaySpaces,
      let displays = copyManagedDisplaySpaces(connectionID)?.takeRetainedValue()
        as? [[String: Any]]
    else {
      return [:]
    }

    let displayIDs = Self.displayIDsByUUID()
    var current: [CGDirectDisplayID: Int] = [:]

    for display in displays {
      guard let uuid = display["Display Identifier"] as? String,
        let displayID = displayIDs[uuid],
        let space = display["Current Space"] as? [String: Any],
        let id = (space["ManagedSpaceID"] as? Int) ?? (space["id64"] as? Int)
      else {
        continue
      }

      current[displayID] = id
    }

    return current
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

  /// Shows a Space, including one with nothing on it — which no public call can do,
  /// because the public way to reach a Space is to activate a window that lives
  /// there and an empty desktop has none.
  ///
  /// Measured: the active Space went from 4313 to 4555, an empty desktop, and back.
  @discardableResult
  func focus(space: Int, on displayID: CGDirectDisplayID) -> Bool {
    guard let connectionID, let setCurrentSpace,
      let uuid = Self.uuidsByDisplayID()[displayID]
    else {
      logger.warning("No display UUID for \(displayID); cannot show that Space")
      return false
    }

    logger.info("Showing Space \(space) on display \(uuid)")
    setCurrentSpace(connectionID, uuid as CFString, UInt64(space))
    Self.followTheEye(to: displayID)

    return true
  }

  /// Puts the pointer on the display whose Space was just shown.
  ///
  /// macOS switches that display and leaves your attention where it was, so
  /// choosing a Space on the other screen looked like nothing at all: the switch
  /// happened, out of sight. The display under the pointer is the one the system
  /// treats as yours, so moving it is what makes the choice mean "go there".
  private static func followTheEye(to displayID: CGDirectDisplayID) {
    guard let screen = DisplayInfo.screen(for: displayID),
      !screen.frame.contains(NSEvent.mouseLocation)
    else {
      return
    }

    // Cocoa counts from the bottom of the main screen, the warp counts from the
    // top of it, which is the one conversion this needs.
    let centre = CGPoint(x: screen.frame.midX, y: screen.frame.midY)
    let flipped = CGPoint(
      x: centre.x,
      y: (NSScreen.screens.first?.frame.maxY ?? centre.y) - centre.y
    )

    CGWarpMouseCursorPosition(flipped)
    CGAssociateMouseAndMouseCursorPosition(1)
  }

  private static func uuidsByDisplayID() -> [CGDirectDisplayID: String] {
    displayIDsByUUID().reduce(into: [:]) { result, entry in
      result[entry.value] = entry.key
    }
  }

  /// The Space showing now, which is what orders the groups: the one you are on
  /// comes first.
  func activeSpace() -> Int? {
    guard let connectionID, let getActiveSpace else {
      return nil
    }

    return Int(getActiveSpace(connectionID))
  }

  /// Names one display's Spaces as the system does: desktops counted among
  /// themselves, a fullscreen Space called after the application filling it —
  /// because "Space 4" for a fullscreen window would be a number nothing else uses.
  static func names(
    for ordered: [SpaceQuery.Space],
    on displayID: CGDirectDisplayID,
    windows: [WindowInfo],
    spaces: [CGWindowID: Int]
  ) -> [WindowSectionID: String] {
    var names: [WindowSectionID: String] = [:]
    var desktopNumber = 0

    for (index, space) in ordered.enumerated() {
      let id = WindowSectionID(displayID: displayID, spaceIndex: index)

      guard space.isFullscreen else {
        desktopNumber += 1
        names[id] = String(localized: "Desktop \(desktopNumber)")
        continue
      }

      let occupant = windows.first { spaces[$0.id] == space.id }
      names[id] = occupant?.appName ?? String(localized: "Fullscreen")
    }

    return names
  }

  private static func symbol(
    _ handle: UnsafeMutableRawPointer,
    _ name: String,
    _ olderName: String
  ) -> UnsafeMutableRawPointer? {
    dlsym(handle, name) ?? dlsym(handle, olderName)
  }
}
