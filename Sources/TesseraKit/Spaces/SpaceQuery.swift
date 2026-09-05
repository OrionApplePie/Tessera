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
  private let didOpen: Bool
  private let isEnabled: Bool
  private let logger: AppLogger

  var isAvailable: Bool {
    connectionID != nil && copySpacesForWindows != nil
  }

  init(enabled: Bool, debugMode: Bool) {
    self.logger = AppLogger(debugMode: debugMode, category: .preview)
    self.isEnabled = enabled

    guard enabled, let handle = dlopen(Self.frameworkPath, RTLD_LAZY) else {
      self.connectionID = nil
      self.copySpacesForWindows = nil
      self.getActiveSpace = nil
      self.copyManagedDisplaySpaces = nil
      self.didOpen = false

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
    self.didOpen = true
    if spaces == nil || connection == nil {
      logger.warning(
        "SkyLight is missing the calls this needs; Spaces will be inferred from what is on screen")
    }
  }

  /// What the window server actually offered when it was asked.
  ///
  /// These are private calls in a framework Apple documents nowhere, and the way
  /// they go is not a crash but a quiet nothing: a symbol that has been renamed
  /// resolves to nil, and Spaces silently become guesswork. Checking at startup and
  /// saying so is the difference between a switcher that has degraded and one that
  /// looks broken for no reason.
  struct Availability: Equatable, Sendable {
    /// Whether the configuration asked for the private calls at all.
    let isEnabled: Bool
    /// Whether SkyLight itself opened.
    let isOpen: Bool
    /// Which of the calls answered to a name, in the order they are needed.
    let found: [String: Bool]

    var missing: [String] {
      found.filter { !$0.value }.keys.sorted()
    }

    /// Everything asked for is there. An installation that was never asked counts
    /// as complete: nothing is missing that was wanted.
    var isComplete: Bool {
      !isEnabled || (isOpen && missing.isEmpty)
    }

    /// One line, for a log or a terminal.
    var summary: String {
      guard isEnabled else {
        return "off by configuration; Spaces are inferred from what is on screen together"
      }

      guard isOpen else {
        return "SkyLight did not open; Spaces are inferred from what is on screen together"
      }

      guard !missing.isEmpty else {
        return "all \(found.count) calls available"
      }

      return "missing \(missing.joined(separator: ", ")); Spaces are inferred instead"
    }
  }

  /// The report, which is only ever what was found at startup: a symbol does not
  /// appear later in the life of a process.
  var availability: Availability {
    Availability(
      isEnabled: isEnabled,
      isOpen: didOpen,
      found: [
        "SLSMainConnectionID": connectionID != nil,
        "SLSCopySpacesForWindows": copySpacesForWindows != nil,
        "SLSGetActiveSpace": getActiveSpace != nil,
        "SLSCopyManagedDisplaySpaces": copyManagedDisplaySpaces != nil,
      ]
    )
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
    managedDisplays().reduce(into: [:]) { result, display in
      result[display.0] = display.1
    }
  }

  /// The number macOS gives each desktop — the N in the "Switch to Desktop N"
  /// shortcut, which is the only thing that actually shows a Space.
  ///
  /// Counted across every display in the system's own order, skipping fullscreen
  /// Spaces because those are not numbered: measured on a machine whose built-in
  /// display holds desktops 1 and 2, the external display's only desktop answers
  /// to ⌃3, and it answers wherever the pointer happens to be.
  func desktopNumbers() -> [Int: Int] {
    Self.desktopNumbers(inOrder: managedDisplays().map(\.1))
  }

  nonisolated static func desktopNumbers(inOrder displays: [[Space]]) -> [Int: Int] {
    var numbers: [Int: Int] = [:]
    var desktop = 0

    for spaces in displays {
      for space in spaces where !space.isFullscreen {
        desktop += 1
        numbers[space.id] = desktop
      }
    }

    return numbers
  }

  /// Every display with its Spaces, in the order the window server lists both —
  /// the order the numbering above counts in, and the one a dictionary would lose.
  private func managedDisplays() -> [(CGDirectDisplayID, [Space])] {
    guard let connectionID, let copyManagedDisplaySpaces,
      let displays = copyManagedDisplaySpaces(connectionID)?.takeRetainedValue()
        as? [[String: Any]]
    else {
      return []
    }

    let displayIDs = Self.displayIDsByUUID()

    return displays.compactMap { display in
      guard let uuid = display["Display Identifier"] as? String,
        let displayID = displayIDs[uuid]
      else {
        return nil
      }

      let spaces = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> Space? in
        guard let id = (space["ManagedSpaceID"] as? Int) ?? (space["id64"] as? Int) else {
          return nil
        }

        return Space(id: id, isFullscreen: (space["type"] as? Int) == 4)
      }

      return (displayID, spaces)
    }
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

  /// The display the system treats as active: the one showing the active Space.
  ///
  /// `NSScreen.main` is not that display. It answers the screen of the window with
  /// keyboard focus, and the two disagree exactly where it matters — measured, with
  /// the work happening in a fullscreen window on the external display,
  /// `NSScreen.main` still said the built-in one. The pointer is no better: showing
  /// a Space moves it to that display and it stays there after the attention has
  /// gone back. The active Space follows the focus across displays, and it is what
  /// decides where Spotlight opens.
  func activeDisplay() -> CGDirectDisplayID? {
    guard let active = activeSpace() else {
      return nil
    }

    return currentSpaces().first { $0.value == active }?.key
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
    on displayID: CGDirectDisplayID
  ) -> [WindowSectionID: String] {
    var names: [WindowSectionID: String] = [:]
    var desktopNumber = 0

    for (index, space) in ordered.enumerated() {
      let id = WindowSectionID(displayID: displayID, spaceIndex: index)

      guard space.isFullscreen else {
        desktopNumber += 1
        names[id] = localized("Desktop %lld", desktopNumber)
        continue
      }

      // Named after nothing: the Space of a fullscreen window holds that one
      // window, and the tile under the heading already says which. The mark beside
      // the heading says it is fullscreen, so the application's name in the heading
      // was the same word twice.
      names[id] = ""
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
