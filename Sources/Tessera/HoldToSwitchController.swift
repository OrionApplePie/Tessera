import AppKit
import Carbon.HIToolbox

/// Identifies the riding hotkeys in Carbon's process-wide namespace: 'TRID'.
private let holdSignature = OSType(0x5452_4944)

/// Holds ⌃⌥ with the arrows, and watches for the moment they are let go.
///
/// This is the other way into the overlay, and it works the way ⌘Tab does: ⌃⌥ with
/// an arrow opens the map and moves the highlight, every further arrow moves it
/// again, and letting the modifiers go switches to whatever the highlight is on.
/// Nothing happens on the way there — no Space changes under the hand that is
/// still choosing — so the map stays still and the screen changes once, at the
/// end.
///
/// The keys are held whether or not the overlay is up, which is what lets the
/// first arrow open it. Carbon is used for the presses because it consumes them —
/// ⌃⌥ with an arrow reaches no application while this is running — and an
/// `NSEvent` monitor for the release, because Carbon reports presses only.
@MainActor
final class HoldToSwitchController {
  private static let modifiers: HotkeyModifiers = [.control, .option]

  private static let directions: [(direction: OverlayGrid.Direction, key: String)] = [
    (.left, "left"), (.right, "right"), (.up, "up"), (.down, "down"),
  ]

  private let logger: AppLogger
  private let onMove: @MainActor (OverlayGrid.Direction) -> Void
  private let onCycle: @MainActor (Bool) -> Void
  private let onRelease: @MainActor () -> Void
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var directionsByID: [UInt32: OverlayGrid.Direction] = [:]
  /// Tab, and Tab with shift: the way to the windows behind the front card while
  /// the modifiers are still held. Held here rather than left to the panel's own
  /// keys, because a step can put another application in front mid-choice.
  private static let cycleForwardID: UInt32 = 20
  private static let cycleBackwardID: UInt32 = 21
  private var eventHandler: EventHandlerRef?
  private var releaseWatch: [Any] = []
  private var holding = false

  init(
    debugMode: Bool,
    onMove: @escaping @MainActor (OverlayGrid.Direction) -> Void,
    onCycle: @escaping @MainActor (Bool) -> Void,
    onRelease: @escaping @MainActor () -> Void
  ) {
    self.logger = AppLogger(debugMode: debugMode, category: .trigger)
    self.onMove = onMove
    self.onCycle = onCycle
    self.onRelease = onRelease
  }

  func start() {
    guard hotKeyRefs.isEmpty else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      holdEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard installStatus == noErr else {
      logger.warning("Hold-to-switch hotkeys could not be installed: OSStatus \(installStatus)")
      return
    }

    for (index, entry) in Self.directions.enumerated() {
      guard let key = HotkeyKey(name: entry.key) else {
        continue
      }

      let id = UInt32(index + 1)

      if register(keyCode: key.carbonKeyCode, modifiers: Self.modifiers, id: id, name: entry.key) {
        directionsByID[id] = entry.direction
      }
    }

    register(
      keyCode: UInt32(kVK_Tab), modifiers: Self.modifiers, id: Self.cycleForwardID, name: "tab")
    register(
      keyCode: UInt32(kVK_Tab),
      modifiers: Self.modifiers.union(.shift),
      id: Self.cycleBackwardID,
      name: "shift-tab"
    )

    logger.info("Holding \(hotKeyRefs.count) hold-to-switch hotkeys")
  }

  func stop() {
    for ref in hotKeyRefs {
      UnregisterEventHotKey(ref)
    }

    hotKeyRefs = []
    directionsByID = [:]
    stopWatchingTheModifiers()

    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  @discardableResult
  private func register(
    keyCode: UInt32,
    modifiers: HotkeyModifiers,
    id: UInt32,
    name: String
  ) -> Bool {
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      modifiers.rawValue,
      EventHotKeyID(signature: holdSignature, id: id),
      GetApplicationEventTarget(),
      0,
      &ref
    )

    guard status == noErr, let ref else {
      logger.warning("Hold-to-switch hotkey \(name) refused: OSStatus \(status)")
      return false
    }

    hotKeyRefs.append(ref)

    return true
  }

  fileprivate func handle(id: UInt32) {
    let cycling = id == Self.cycleForwardID || id == Self.cycleBackwardID

    guard let direction = directionsByID[id] ?? (cycling ? .right : nil) else {
      return
    }

    if !holding {
      holding = true
      watchTheModifiers()
    }

    if cycling {
      onCycle(id == Self.cycleForwardID)
    } else {
      onMove(direction)
    }
  }

  /// Carbon says nothing about a key going up, so the release is watched
  /// for separately: locally because this application is in front while the overlay
  /// is up, and globally because a step can put another application in front.
  private func watchTheModifiers() {
    guard releaseWatch.isEmpty else {
      return
    }

    let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      self?.modifiersChanged(to: event.modifierFlags)
      return event
    }

    let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
      MainActor.assumeIsolated {
        self?.modifiersChanged(to: event.modifierFlags)
      }
    }

    releaseWatch = [local, global].compactMap { $0 }
  }

  private func modifiersChanged(to flags: NSEvent.ModifierFlags) {
    let held = HotkeyModifiers(flags)
    guard holding, !held.contains(.control) || !held.contains(.option) else {
      return
    }

    holding = false
    stopWatchingTheModifiers()
    logger.debug("The modifiers were let go; switching to what the highlight is on")
    onRelease()
  }

  private func stopWatchingTheModifiers() {
    for monitor in releaseWatch {
      NSEvent.removeMonitor(monitor)
    }

    releaseWatch = []
  }
}

/// Decoded off the `EventRef` before the hop to the main actor, for the same
/// reason the overlay's own hotkeys are: neither the event nor the context pointer
/// is `Sendable`, while the controller is.
private func holdEventHandler(
  _ callRef: EventHandlerCallRef?,
  _ event: EventRef?,
  _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
  guard let userData else {
    return OSStatus(eventNotHandledErr)
  }

  var pressedID = EventHotKeyID()
  let status = GetEventParameter(
    event,
    EventParamName(kEventParamDirectObject),
    EventParamType(typeEventHotKeyID),
    nil,
    MemoryLayout<EventHotKeyID>.size,
    nil,
    &pressedID
  )

  guard status == noErr, pressedID.signature == holdSignature else {
    return OSStatus(eventNotHandledErr)
  }

  let controller = Unmanaged<HoldToSwitchController>.fromOpaque(userData).takeUnretainedValue()
  let id = pressedID.id

  MainActor.assumeIsolated {
    controller.handle(id: id)
  }

  return noErr
}
