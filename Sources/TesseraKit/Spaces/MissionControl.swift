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
  private static let pollStep = Duration.milliseconds(50)

  /// How long a pressed button is given to change the Spaces, and how long
  /// Mission Control is given to go away when it has to be closed first.
  private static let actionDeadline = Duration.milliseconds(2000)

  /// How long one Escape is given to take effect, and how many are sent before
  /// giving up and saying so.
  private static let dismissDeadline = Duration.milliseconds(700)
  private static let dismissAttempts = 3

  private let logger: AppLogger

  init(config: AppConfig) {
    self.logger = AppLogger(debugMode: config.debugMode, category: .trigger)
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

    let before = opened.spaces.count

    guard await press(opened) else {
      await putAway(ofDock: dock)
      return false
    }

    let after = await count(on: displayID, ofDock: dock, changingFrom: before)
    await putAway(ofDock: dock)

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
  /// Waited for rather than sampled once: a desktop appears and goes with an
  /// animation of its own, and reading the bar back too early counts the Spaces as
  /// they were.
  private func count(
    on displayID: CGDirectDisplayID,
    ofDock dock: pid_t,
    changingFrom before: Int
  ) async -> Int {
    var last = before

    _ = await waitUntil {
      guard let now = Self.visibleBars(ofDock: dock).first(where: { $0.displayID == displayID })
      else {
        return false
      }

      last = now.spaces.count

      return last != before
    }

    return last
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
  /// again until the bars are gone.
  private func putAway(ofDock dock: pid_t) async {
    for _ in 0..<Self.dismissAttempts {
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
