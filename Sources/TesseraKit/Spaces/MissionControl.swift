import AppKit
import ApplicationServices
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Creating and closing Spaces, by pressing the buttons Mission Control already has.
///
/// The screen shows Mission Control for about a second while this happens, which is
/// the price of the only door macOS leaves open: see `MissionControlTree` for why
/// the window server's own calls are not that door. Adding and closing a desktop
/// are rare enough for a visible second to be honest rather than annoying —
/// switching between Spaces stays on the instant shortcut in `DesktopSwitcher`.
///
/// Each action says whether it happened, and says it by counting the Spaces on that
/// display before and after rather than by trusting the button press: `AXPress`
/// reports success for a press that was delivered, not for a desktop that appeared.
@MainActor
struct MissionControl {
  /// What the drag needs to know about a window: which one it is, what Mission
  /// Control draws it under, and which display it is on.
  struct Window {
    let id: CGWindowID
    let title: String
    let appName: String
    let displayID: CGDirectDisplayID

    /// What to call it in a log line.
    var name: String {
      title.isEmpty ? appName : "\(appName): \(title)"
    }
  }

  /// What an action is expected to do to the number of Spaces on a display.
  enum Change {
    case more
    case fewer
  }

  /// Mission Control has lived here since Catalina. Opened as an application
  /// rather than by synthesising ⌃↑, because that shortcut is the user's to
  /// rebind or switch off and this must not depend on it.
  private static let applicationPath = "/System/Applications/Mission Control.app"

  /// How long the bars are waited for, and how often they are looked for. The wait
  /// covers the opening animation; the step is short enough not to add to it.
  private static let openDeadline = Duration.milliseconds(2500)
  private static let pollStep = Duration.milliseconds(20)

  /// How long a pressed button is given to change the Spaces, and how long
  /// Mission Control is given to go away when it has to be closed first.
  private static let actionDeadline = Duration.milliseconds(2000)

  /// How long the bar is given to show what the press did, before the screen is
  /// handed back.
  private static let barSettle = Duration.milliseconds(600)

  /// How long one Escape is given to take effect, and how many are sent before
  /// giving up and saying so.
  private static let dismissDeadline = Duration.milliseconds(300)
  private static let dismissAttempts = 5

  private let logger: AppLogger
  /// Asked how many Spaces a display has once the screen has been given back.
  private let spaces: SpaceQuery

  init(config: AppConfig) {
    self.logger = AppLogger(debugMode: config.debugMode, category: .trigger)
    self.spaces = SpaceQuery(enabled: config.usesPrivateSpaceAPI, debugMode: config.debugMode)
  }

  /// Adds a desktop to one display. Says whether one appeared.
  func addDesktop(on displayID: CGDirectDisplayID) async -> Bool {
    await act(on: displayID, wanting: .more) { bar async in
      guard let add = bar.add else {
        logger.warning("Mission Control shows no button for adding a desktop")
        return false
      }

      return AXUIElementPerformAction(add, kAXPressAction as CFString) == .success
    }
  }

  /// Closes one Space of one display, by its index in that display's list — the
  /// same index the overlay's sections are numbered by. Says whether it went.
  ///
  /// The last desktop of a display cannot be closed. macOS says so by leaving the
  /// Space where it is, which the count then reports — not by refusing the press.
  func closeSpace(at index: Int, on displayID: CGDirectDisplayID) async -> Bool {
    await act(on: displayID, wanting: .fewer) { bar async in
      guard let space = bar.spaces[safe: index] else {
        logger.warning("Display \(displayID) has no Space \(index) to close")
        return false
      }

      // Waited for rather than checked. Measured: for the first moment after
      // Mission Control opens, every button lists `AXPress` and nothing else, and
      // the remove action turns up a beat later — so refusing a button that had
      // not yet admitted it could be closed refused Spaces that closed perfectly
      // well when simply asked. If it never admits it, the press goes out anyway
      // and the count decides.
      let ready = await waitUntil {
        MissionControlTree.actions(of: space).contains(MissionControlTree.removeAction)
      }

      if !ready {
        logger.info("Space \(index) of display \(displayID) never offered to close")
      }

      return AXUIElementPerformAction(space, MissionControlTree.removeAction as CFString)
        == .success
    }
  }

  /// Moves a window to another Space of its display, by dragging its thumbnail
  /// onto that Space in Mission Control's bar. Says whether the window really went.
  ///
  /// This is the only way that works. Every private call for it is shut on macOS 15
  /// — see `docs/mechanisms.md` — and Mission Control's own gesture is not shut,
  /// because it is a gesture: a press, a path and a release, which anyone may make.
  ///
  /// The answer comes from the window server, which is asked where the window is
  /// before and after. The thumbnail leaving the screen would only say that Mission
  /// Control redrew.
  func move(_ window: Window, toSpaceAt index: Int, on target: CGDirectDisplayID) async -> Bool {
    guard AXIsProcessTrusted() else {
      logger.warning("Accessibility is not granted, so no window can be dragged")
      return false
    }

    guard let dock = Self.dockProcess() else {
      logger.warning("The Dock is not running, so there is no Mission Control to open")
      return false
    }

    let before = spaces.spaces(of: [window.id])[window.id]

    await openFresh(ofDock: dock)

    guard let places = await places(of: window, toSpaceAt: index, on: target, ofDock: dock) else {
      await putAway(ofDock: dock)
      return false
    }

    await PointerDrag.drag(from: places.0, to: places.1)
    await putAway(ofDock: dock)

    let moved = await waitUntil { spaces.spaces(of: [window.id])[window.id] != before }

    logger.info("Moved \(window.name) to Space \(index) of its display: \(moved)")

    return moved
  }

  /// Where the drag starts and where it lands, or nothing when either is missing.
  ///
  /// The window is missing whenever it is not on the Space its display is showing:
  /// Mission Control draws that Space's windows and no others.
  private func places(
    of window: Window,
    toSpaceAt index: Int,
    on display: CGDirectDisplayID,
    ofDock dock: pid_t
  ) async -> (CGPoint, CGPoint)? {
    guard let home = await bar(on: window.displayID, ofDock: dock) else {
      logger.warning("Mission Control did not show a Spaces bar for that display")
      return nil
    }

    // The bar the window lands on need not be its own. Measured: a window dragged
    // from the built-in display onto a Space in the external display's bar goes
    // there, display and Space at once.
    let bar =
      display == window.displayID ? home : await self.bar(on: display, ofDock: dock)

    guard let bar, let target = bar.spaces[safe: index],
      let landing = MissionControlTree.frame(of: target)
    else {
      logger.warning("Display \(display) has no Space \(index) to drop a window on")
      return nil
    }

    let drawn = MissionControlTree.thumbnails(
      ofDock: dock, on: window.displayID, besides: [home, bar])

    guard
      let thumbnail = MissionControlTree.thumbnail(
        titled: window.title, orNamed: window.appName, among: drawn)
    else {
      logger.info(
        "Mission Control is not drawing \(window.name); it shows: \(drawn.map(\.title))")
      return nil
    }

    return (
      CGPoint(x: thumbnail.frame.midX, y: thumbnail.frame.midY),
      CGPoint(x: landing.midX, y: landing.midY)
    )
  }

  /// Opens Mission Control, presses something in one display's bar, checks what it
  /// did to that display, and puts Mission Control away again.
  private func act(
    on displayID: CGDirectDisplayID,
    wanting change: Change,
    _ press: (MissionControlTree.Bar) async -> Bool
  ) async -> Bool {
    guard AXIsProcessTrusted() else {
      logger.warning("Accessibility is not granted, so Mission Control cannot be worked")
      return false
    }

    guard let dock = Self.dockProcess() else {
      logger.warning("The Dock is not running, so there is no Mission Control to open")
      return false
    }

    await openFresh(ofDock: dock)

    guard let opened = await bar(on: displayID, ofDock: dock) else {
      logger.warning("Mission Control did not show a Spaces bar for display \(displayID)")
      await putAway(ofDock: dock)
      return false
    }

    let before = spaceCount(on: displayID) ?? opened.spaces.count
    let shown = opened.spaces.count

    guard await press(opened) else {
      await putAway(ofDock: dock)
      return false
    }

    // The bar is given its moment to redraw before the key that closes Mission
    // Control goes out. Measured, this is the whole difference between a flash and
    // a pause: Escape sent while the Space is still appearing is swallowed, the
    // retry comes 700 ms later, and Mission Control sits on the screen for 1.1 s —
    // against 0.7 s when the press is allowed to land first. It costs 40-80 ms.
    _ = await waitUntil(within: Self.barSettle) {
      Self.visibleBars(ofDock: dock).first { $0.displayID == displayID }?.spaces.count != shown
    }

    await putAway(ofDock: dock)

    let after = await count(on: displayID, ofDock: dock, changingFrom: before)

    logger.info("Display \(displayID): Spaces went from \(before) to \(after)")

    return Self.happened(change, before: before, after: after)
  }

  /// Mission Control, opened from a known state.
  ///
  /// Two measured reasons for the detour. Opening it while it is already showing
  /// puts it away — it is a toggle, not a command — so a previous action that left
  /// it up made the next one close it and find no bars, which reads as "the button
  /// did nothing". And a bar left over from that earlier showing hands out elements
  /// that no longer answer: pressing one reported success and removed nothing.
  private func openFresh(ofDock dock: pid_t) async {
    if !Self.visibleBars(ofDock: dock).isEmpty {
      await putAway(ofDock: dock)
    }

    NSWorkspace.shared.open(URL(fileURLWithPath: Self.applicationPath))
  }

  /// The number of Spaces on a display once it has moved, or the number it started
  /// at if it never does.
  ///
  /// Waited for rather than sampled once: a Space appears and goes with an
  /// animation of its own, and asking too early counts the Spaces as they were.
  private func count(
    on displayID: CGDirectDisplayID,
    ofDock dock: pid_t,
    changingFrom before: Int
  ) async -> Int {
    var last = before

    _ = await waitUntil {
      guard
        let now = spaceCount(on: displayID)
          ?? Self.visibleBars(ofDock: dock)
          .first(where: { $0.displayID == displayID })?.spaces.count
      else {
        return false
      }

      last = now

      return last != before
    }

    return last
  }

  /// How many Spaces a display has, according to the window server.
  ///
  /// Nothing when the private Space calls are switched off, and then the bar is
  /// counted instead — which works, but only while Mission Control is still up.
  private func spaceCount(on displayID: CGDirectDisplayID) -> Int? {
    spaces.orderedSpaces()[displayID]?.count
  }

  /// Polls until something is true, or until the deadline. Says which.
  private func waitUntil(
    within limit: Duration = Self.actionDeadline,
    _ done: () -> Bool
  ) async -> Bool {
    let deadline = ContinuousClock.now + limit

    while ContinuousClock.now < deadline {
      if done() {
        return true
      }

      try? await Task.sleep(for: Self.pollStep)
    }

    return false
  }

  private static func visibleBars(ofDock dock: pid_t) -> [MissionControlTree.Bar] {
    MissionControlTree.bars(ofDock: dock, displays: MissionControlTree.displayBounds())
  }

  /// Whether the count moved the way the action meant it to.
  nonisolated static func happened(_ change: Change, before: Int, after: Int) -> Bool {
    switch change {
    case .more:
      return after > before
    case .fewer:
      return after < before
    }
  }

  /// One display's bar, waited for: the tree exists only once Mission Control has
  /// finished opening.
  private func bar(
    on displayID: CGDirectDisplayID,
    ofDock dock: pid_t
  ) async -> MissionControlTree.Bar? {
    let displays = MissionControlTree.displayBounds()
    let deadline = ContinuousClock.now + Self.openDeadline

    while ContinuousClock.now < deadline {
      let bars = MissionControlTree.bars(ofDock: dock, displays: displays)

      // One display is the ordinary case and its bar is unmistakable, so a bar
      // whose display could not be worked out is still that display's bar.
      let named = bars.first { $0.displayID == displayID }
      let only = bars.count == 1 ? bars.first : nil

      if let bar = named ?? only {
        return bar
      }

      try? await Task.sleep(for: Self.pollStep)
    }

    return nil
  }

  /// Puts Mission Control away, and makes sure it went.
  ///
  /// Measured: one Escape, posted the moment the Spaces have finished changing, is
  /// sometimes swallowed — the animation is still running — and Mission Control
  /// stays on the screen. That is both an eyesore and a trap, since the next
  /// action would then toggle it shut instead of opening it. So the key goes out
  /// again until the bars are gone, and soon: waiting 700 ms between attempts left
  /// Mission Control up for 1.2 s on the external display against 0.6 s on the
  /// built-in, which was the whole of the difference between them.
  private func putAway(ofDock dock: pid_t) async {
    for _ in 0..<Self.dismissAttempts {
      // Looked at before every attempt, not only after: an Escape sent at a
      // Mission Control that has already gone lands in whatever is in front, and
      // Escape means something there.
      guard !Self.visibleBars(ofDock: dock).isEmpty else {
        return
      }

      escape()

      let gone = await waitUntil(within: Self.dismissDeadline) {
        Self.visibleBars(ofDock: dock).isEmpty
      }

      if gone {
        return
      }
    }

    logger.warning("Mission Control would not close")
  }

  /// Sends the key that closes Mission Control.
  private func escape() {
    let key = CGKeyCode(kVK_Escape)

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    else {
      logger.warning("Could not build the keystroke that closes Mission Control")
      return
    }

    down.post(tap: .cghidEventTap)
    up.post(tap: .cghidEventTap)
  }

  private static func dockProcess() -> pid_t? {
    NSRunningApplication
      .runningApplications(withBundleIdentifier: "com.apple.dock")
      .first?
      .processIdentifier
  }
}
