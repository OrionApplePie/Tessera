import AppKit
import CoreGraphics
import Foundation

/// Shows a desktop Space by pressing the shortcut macOS itself binds to it.
///
/// This is the only way found that moves the screen. The private
/// `SLSManagedDisplaySetCurrentSpace` writes the window server's "Current Space"
/// field and stops there: measured, the field went from 5847 to 4556 while the
/// external display went on showing the same fullscreen window, which is why
/// choosing an empty desktop used to look like nothing at all — the bookkeeping
/// agreed the Space had changed and the screen disagreed. Synthesising the
/// system's own ⌃← and ⌃→ does not work either, with or without the function flag
/// their preference entry carries. Synthesising ⌃N does: measured, ⌃3 posted from
/// this process took the external display from 5847 to 4556 and a screenshot of
/// that display showed bare wallpaper.
///
/// The shortcut is read from the system rather than assumed, because it is the
/// user's to rebind or switch off — and past the last one macOS binds, a desktop
/// has no shortcut and cannot be reached this way at all.
@MainActor
struct DesktopSwitcher {

  /// "Switch to Desktop 1" and the seven entries after it, in the table of
  /// shortcuts macOS keeps for itself. It binds no ninth, so a ninth desktop has
  /// no way in.
  nonisolated static let firstSymbolicID = 118
  nonisolated static let desktopLimit = 8

  /// How long the key is held down.
  ///
  /// Not a tuned delay but a threshold: posted back to back, the down and the up
  /// cancel and the shortcut does nothing at all — measured, the display stayed on
  /// the Space it was showing, while the same two events with a moment between
  /// them switched it. The window server wants the key held, briefly.
  private static let keyDownHold = Duration.milliseconds(20)

  /// How long the pointer is given to arrive before it is clicked with, and how long
  /// the button is held. Both are thresholds rather than tuned delays: without the
  /// first the press lands where the pointer used to be, without the second there is
  /// no click at all.
  private static let pointerSettle = Duration.milliseconds(120)
  private static let clickHold = Duration.milliseconds(60)

  private let logger: AppLogger
  /// How long the handover below is given before the keystroke goes out anyway.
  private let settle: Duration

  init(config: AppConfig) {
    self.settle = .seconds(config.activationSettleSeconds)
    self.logger = AppLogger(debugMode: config.debugMode, category: .trigger)
  }

  /// The shortcut for one desktop, or nothing when the user has switched it off.
  nonisolated static func shortcut(
    forDesktop number: Int,
    among hotkeys: [SystemHotkey]
  ) -> SystemHotkey? {
    guard (1...desktopLimit).contains(number) else {
      return nil
    }

    return hotkeys.first { $0.id == firstSymbolicID + number - 1 }
  }

  /// Presses the shortcut, and says whether there was one to press.
  ///
  /// A `true` here means the keystroke went out, not that the Space changed — the
  /// caller is the one that can read back what the display is showing now, and
  /// does.
  func show(
    desktop number: Int?,
    on displayID: CGDirectDisplayID,
    handingBack: Bool,
    showing: () -> Bool
  ) async {
    guard let number else {
      logger.warning("That Space has no desktop number, so no shortcut shows it")
      return
    }

    // A desktop already on screen has nothing to switch to — measured, its shortcut
    // does nothing at all — but choosing it still means "take me there", and on
    // another display that is a real move: macOS shifts its attention on a click or
    // an activation, never on the pointer alone. So the pointer goes there and the
    // desktop is clicked, which is what a person does. Only with the overlay gone,
    // though: while it is up and being stepped through, the click would land on the
    // panel itself.
    guard !showing() else {
      logger.info("Desktop \(number) is already showing; going there instead of switching")

      if handingBack {
        await Self.goToTheDesktop(on: displayID)
      }

      return
    }

    guard let shortcut = Self.shortcut(forDesktop: number, among: SystemHotkeys.enabled()) else {
      logger.warning(
        """
        Desktop \(number) has no shortcut in System Settings > Keyboard > Shortcuts \
        > Mission Control, so it cannot be shown
        """
      )
      return
    }

    // Posting a keystroke is one of the things Accessibility gates, and a denied
    // post reports nothing: the event is simply dropped.
    guard AXIsProcessTrusted() else {
      logger.warning("Accessibility is not granted, so the keystroke showing a desktop is dropped")
      return
    }

    if handingBack {
      await handTheKeyboardToTheDesktop()
    }

    logger.info("Showing desktop \(number) with the system shortcut")
    await press(shortcut)

    let arrived = await waitUntil(showing)
    logger.info("Desktop \(number) on display \(displayID): arrived=\(arrived)")

    // Arriving is not the same as being there. The keyboard was handed to Finder to
    // make the switch stick, and Finder's front window can be on another display —
    // measured, switching to an empty desktop on the display you are already on
    // left the other one active, menu bar and all. The desktop just shown has
    // nothing on it, so the same click that goes to a desktop already shown puts
    // the attention where it was asked to go.
    if arrived && handingBack {
      await Self.goToTheDesktop(on: displayID)
    }
  }

  /// Gives the keyboard to the application that owns the desktop, and waits until
  /// it has taken it, so the keystroke lands with an ordinary application in front
  /// and nothing pending.
  ///
  /// Measured, and the reason this is not left to macOS. Pressing the shortcut with
  /// this application in front makes macOS pick a front application of its own — the
  /// one from the Space being left — and that application brings its Space back:
  /// 600 ms after the switch the front had moved, 300 ms later the display had
  /// followed it. Handing the keyboard to that same application first does fix the
  /// switch, but it leaves a fullscreen application in front of a desktop it owns no
  /// window on, and then the next activation of any kind — opening this overlay
  /// again — sends the display back to it, which is what "the overlay opens on the
  /// previous desktop" was.
  ///
  /// The desktop belongs to Finder, and Finder in front is the state a person ends
  /// up in having switched desktops themselves. It is activated without raising its
  /// windows: measured, that leaves every other display where it was, while asking
  /// AppleScript to activate Finder raised a window and took the other display off
  /// its fullscreen Space with it.
  ///
  /// Nobody to hand it to means nothing to wait for — the case while the overlay
  /// stays up and Spaces are stepped through with the keyboard.
  ///
  /// The wait is read rather than subscribed to: the activation notification can
  /// arrive before there is anything listening for it, and waiting for one that has
  /// already been and gone runs to the deadline every time. The twenty milliseconds
  /// are the granularity of the answer, not a delay anybody tuned.
  private func handTheKeyboardToTheDesktop() async {
    guard NSApp.isActive else {
      return
    }

    Self.desktopOwner?.activate(options: [])

    let deadline = ContinuousClock.now + settle

    while NSApp.isActive, ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(20))
    }
  }

  /// Finder draws the desktop and its icons, and no API says as much — its bundle
  /// identifier is the only way to name the application that owns a desktop.
  static var desktopOwner: NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first
  }

  /// Waits for the display to actually show it, which is what makes the answer worth
  /// anything: the private call this replaced reported success out of a field it had
  /// written itself, and was believed.
  ///
  /// It is also what lets the overlay stay up until the Space has changed, and that
  /// order is the whole trick. Pressing while the overlay is still on screen keeps
  /// this application in front, and macOS then hands the desktop to Finder by
  /// itself. Pressing once the overlay was gone left the application whose Space had
  /// just been left in front, and it brought that Space back — first as an instant
  /// undo, and then as an overlay that opened on the Space before.
  private func waitUntil(_ arrived: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + settle

    while ContinuousClock.now < deadline {
      if arrived() {
        return true
      }

      try? await Task.sleep(for: .milliseconds(20))
    }

    return false
  }

  private func press(_ shortcut: SystemHotkey) async {
    let flags = Self.eventFlags(shortcut.modifiers)
    let key = CGKeyCode(shortcut.keyCode)

    guard let down = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: true),
      let up = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: false)
    else {
      logger.warning("Could not build the keystroke that shows a desktop")
      return
    }

    down.flags = flags
    up.flags = flags

    // The HID tap rather than the session one: the window server reads its own
    // shortcuts below every application, so an event posted further up the chain
    // reaches the front application and never the shortcut.
    down.post(tap: .cghidEventTap)
    try? await Task.sleep(for: Self.keyDownHold)
    up.post(tap: .cghidEventTap)
  }

  /// The system stores modifiers as a Cocoa mask and Carbon reads them as its own;
  /// a posted event needs the third spelling.
  private static func eventFlags(_ modifiers: HotkeyModifiers) -> CGEventFlags {
    var flags: CGEventFlags = []

    if modifiers.contains(.control) {
      flags.insert(.maskControl)
    }
    if modifiers.contains(.option) {
      flags.insert(.maskAlternate)
    }
    if modifiers.contains(.shift) {
      flags.insert(.maskShift)
    }
    if modifiers.contains(.command) {
      flags.insert(.maskCommand)
    }

    return flags
  }

  /// How far into a menu bar the application menus reach, plus room to clear them.
  ///
  /// Asked of whichever application is in front, because those are the menus drawn
  /// on every display's bar. Nothing between the end of them and the status items on
  /// the right belongs to anything, which is what makes it safe to click.
  ///
  /// Falls back to the middle of the bar when Accessibility will not say — half way
  /// is past the menus of any ordinary application and short of a plausible row of
  /// status items — and never goes past three quarters of the width, where those
  /// status items live.
  @MainActor
  private static func emptyPointInMenuBar(ofWidth width: CGFloat) -> CGFloat {
    let fallback = width * 0.5
    let ceiling = width * 0.75

    guard let processID = NSWorkspace.shared.frontmostApplication?.processIdentifier,
      let end = menusEnd(ofProcess: processID)
    else {
      return min(fallback, ceiling)
    }

    return pointPastMenus(endingAt: end, barWidth: width)
  }

  /// Where to click, given where the menus end. Extracted from the asking so the
  /// arithmetic can be tested: what Accessibility answers is the machine's, but
  /// what is done with the answer is ours.
  ///
  /// A little past the last menu, never nearer the left than a fifth of the bar —
  /// an application that reports no menus at all should not be taken at its word —
  /// and never past three quarters of it, where the status items are.
  nonisolated static func pointPastMenus(endingAt end: CGFloat, barWidth: CGFloat) -> CGFloat {
    min(max(end + 24, barWidth * 0.2), barWidth * 0.75)
  }

  /// Where the last menu of an application ends, measured from the left of the bar.
  private static func menusEnd(ofProcess processID: pid_t) -> CGFloat? {
    let application = AXUIElementCreateApplication(processID)
    var barValue: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(application, kAXMenuBarAttribute as CFString, &barValue)
        == .success,
      let barValue, CFGetTypeID(barValue) == AXUIElementGetTypeID()
    else {
      return nil
    }

    var itemsValue: CFTypeRef?

    guard
      AXUIElementCopyAttributeValue(
        unsafeDowncast(barValue, to: AXUIElement.self), kAXChildrenAttribute as CFString,
        &itemsValue) == .success,
      let items = itemsValue as? [AXUIElement]
    else {
      return nil
    }

    let ends = items.compactMap { item -> CGFloat? in
      var frameValue: CFTypeRef?

      guard
        AXUIElementCopyAttributeValue(item, "AXFrame" as CFString, &frameValue) == .success,
        let frameValue, CFGetTypeID(frameValue) == AXValueGetTypeID()
      else {
        return nil
      }

      var frame = CGRect.zero

      guard AXValueGetValue(unsafeDowncast(frameValue, to: AXValue.self), .cgRect, &frame) else {
        return nil
      }

      return frame.maxX
    }

    return ends.max()
  }

  /// Moves the attention to a display, by clicking its menu bar.
  ///
  /// The pointer alone is not enough: measured, moving it leaves the active Space —
  /// the one that decides where Spotlight opens and which display carries the menu
  /// bar — exactly where it was. A click moves it, but not just any click: clicking
  /// the wallpaper is what "Click wallpaper to reveal desktop" listens for, and that
  /// setting is on by default. Measured, our click on an empty desktop slid every
  /// window on the other display aside — two Finder windows ended up parked at its
  /// bottom edge, which is what "the windows slide down" was.
  ///
  /// The menu bar is the one part of a display that is always there, belongs to no
  /// window, and answers a click by making that display the active one — measured,
  /// it moved the active Space across while every window stayed where it was.
  ///
  /// Where in the bar, though, is not a fraction of its width. A third of the way in
  /// is empty on a wide display and lands on "Window" on a laptop — Finder's menus
  /// reach that far, and the click opened the menu instead of moving anything. So
  /// the application menus are measured through Accessibility and the click goes
  /// just past the last of them, which is bar and nothing else.
  private static func goToTheDesktop(on displayID: CGDirectDisplayID) async {
    // Where the pointer is now, so it can be put back. A posted click carries its
    // own location and takes the pointer with it, and leaving it on another
    // display's menu bar is moving something the switcher was not asked to move.
    let pointerWas = CGEvent(source: nil)?.location
    let bounds = CGDisplayBounds(displayID)
    let point = CGPoint(
      x: bounds.minX + emptyPointInMenuBar(ofWidth: bounds.width), y: bounds.minY + 6)

    let click = { (type: CGEventType) in
      CGEvent(
        mouseEventSource: nil,
        mouseType: type,
        mouseCursorPosition: point,
        mouseButton: .left
      )
    }

    guard let down = click(.leftMouseDown), let up = click(.leftMouseUp) else {
      return
    }

    // Emptied rather than left alone. An event built without a source of its own
    // carries the modifier state as it stands, and the keystroke this file posts
    // holds control: measured, the click that followed arrived as a control-click
    // and opened a contextual menu instead of going anywhere. Nobody was holding a
    // key — the flag was ours.
    down.flags = []
    up.flags = []

    try? await Task.sleep(for: pointerSettle)
    down.post(tap: .cghidEventTap)
    try? await Task.sleep(for: clickHold)
    up.post(tap: .cghidEventTap)

    guard let pointerWas else {
      return
    }

    // After the click, not before it: warped back too early, the pointer is where
    // it started but the click has not been read yet, and the attention stays where
    // it was.
    try? await Task.sleep(for: clickHold)
    CGWarpMouseCursorPosition(pointerWas)
    CGAssociateMouseAndMouseCursorPosition(1)
  }

  /// Puts the pointer on the display whose Space was just shown.
  ///
  /// macOS switches that display and leaves your attention where it was, so
  /// choosing a Space on the other screen looked like nothing: the switch
  /// happened, out of sight. The display under the pointer is the one the system
  /// treats as yours, so moving it is what makes the choice mean "go there".
}
