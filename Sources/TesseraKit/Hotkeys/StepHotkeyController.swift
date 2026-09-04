import Carbon.HIToolbox
import Foundation

/// Identifies the stepping hotkeys in Carbon's process-wide namespace: 'TSTP'.
private let stepSignature = OSType(0x5453_5450)

/// Holds the arrow keys system-wide for as long as the overlay is up.
///
/// Stepping onto a window on another Space has to bring its application forward,
/// and macOS gives the keyboard to whichever application is active — so the panel
/// loses the keys on the first such step and the mode dies after one move, which
/// is what "it moved a few times and then froze" was.
///
/// A Carbon hotkey is delivered whoever is frontmost, which is exactly the
/// property needed. They are registered when the overlay opens and released when
/// it closes, so nothing outside the overlay is held: `⌃⌥` with an arrow means
/// nothing to this application the rest of the time.
@MainActor
final class StepHotkeyController {
  /// Two combinations, and they do different things. `⌃⌥⇧` steps: it shows the
  /// Space and raises the window, which activates another application. `⌃⌥` only
  /// moves the highlight, and is held for the same reason the arrows are — an arrow
  /// nobody handles is what macOS answers with a beep, and held down that is the
  /// trilling sound this was reported as. It was briefly made to step as well; that
  /// turned every press into an activation, and the overlay went away under the
  /// user's hands while they were still pressing.
  /// Only the stepping combination is held here. ⌃⌥ with an arrow is held by
  /// `RideHotkeyController` instead, and held always rather than only while the
  /// overlay is up: it is what opens the overlay in the first place.
  private static let variants: [(modifiers: HotkeyModifiers, steps: Bool)] = [
    ([.control, .option, .shift], true)
  ]

  private static let directions: [(direction: OverlayGrid.Direction, key: String)] = [
    (.left, "left"), (.right, "right"), (.up, "up"), (.down, "down"),
  ]

  /// Escape is held too, and for the same reason: after a step the keyboard belongs
  /// to the application that came forward, so the overlay's own Escape never
  /// arrives and the panel cannot be dismissed by the key everyone reaches for.
  /// It is held only while the overlay is up, and released with the arrows.
  private static let dismissID: UInt32 = 100

  /// Return, the keypad's Return and Space: the keys that mean "this one, done".
  /// They are held for the same reason Escape is — after a step they would
  /// otherwise reach the application that came forward — and they finish the
  /// switch, because by then the window has already been chosen.
  private static let confirmKeys: [ConfirmKey] = [
    ConfirmKey(code: UInt32(kVK_Return), id: 101, name: "return"),
    ConfirmKey(code: UInt32(kVK_ANSI_KeypadEnter), id: 102, name: "keypad enter"),
    ConfirmKey(code: UInt32(kVK_Space), id: 103, name: "space"),
  ]

  private struct ConfirmKey {
    let code: UInt32
    let id: UInt32
    let name: String
  }

  private let logger: AppLogger
  private let onStep: @MainActor (OverlayGrid.Direction) -> Void
  private let onMove: @MainActor (OverlayGrid.Direction) -> Void
  private let onDismiss: @MainActor () -> Void
  private let onConfirm: @MainActor () -> Void
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var eventHandler: EventHandlerRef?
  private var directionsByID: [UInt32: OverlayGrid.Direction] = [:]
  private var stepsByID: [UInt32: Bool] = [:]

  init(
    debugMode: Bool,
    onStep: @escaping @MainActor (OverlayGrid.Direction) -> Void,
    onMove: @escaping @MainActor (OverlayGrid.Direction) -> Void,
    onDismiss: @escaping @MainActor () -> Void,
    onConfirm: @escaping @MainActor () -> Void
  ) {
    self.logger = AppLogger(debugMode: debugMode, category: .trigger)
    self.onStep = onStep
    self.onMove = onMove
    self.onDismiss = onDismiss
    self.onConfirm = onConfirm
  }

  var isHolding: Bool {
    !hotKeyRefs.isEmpty
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
      stepHotkeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard installStatus == noErr else {
      logger.warning("Stepping hotkeys could not be installed: OSStatus \(installStatus)")
      return
    }

    for (index, entry) in Self.directions.enumerated() {
      guard let key = HotkeyKey(name: entry.key) else {
        continue
      }

      for (variant, kind) in Self.variants.enumerated() {
        let id = UInt32(index + 1 + variant * Self.directions.count)

        let held = register(
          keyCode: key.carbonKeyCode, modifiers: kind.modifiers, id: id, name: entry.key)

        if held {
          directionsByID[id] = entry.direction
          stepsByID[id] = kind.steps
        }
      }
    }

    register(keyCode: UInt32(kVK_Escape), modifiers: [], id: Self.dismissID, name: "escape")

    for key in Self.confirmKeys {
      register(keyCode: key.code, modifiers: [], id: key.id, name: key.name)
    }

    logger.debug("Holding \(hotKeyRefs.count) overlay hotkeys while the overlay is up")
  }

  @discardableResult
  private func register(
    keyCode: UInt32,
    modifiers: HotkeyModifiers,
    id: UInt32,
    name: String
  ) -> Bool {
    var reference: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode,
      modifiers.rawValue,
      EventHotKeyID(signature: stepSignature, id: id),
      GetApplicationEventTarget(),
      0,
      &reference
    )

    guard status == noErr, let reference else {
      logger.warning("Overlay hotkey \(name) refused: OSStatus \(status)")
      return false
    }

    hotKeyRefs.append(reference)
    return true
  }

  func stop() {
    for reference in hotKeyRefs {
      UnregisterEventHotKey(reference)
    }

    hotKeyRefs = []
    directionsByID = [:]
    stepsByID = [:]

    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  fileprivate func handleStep(id: UInt32) {
    if id == Self.dismissID {
      onDismiss()
      return
    }

    if Self.confirmKeys.contains(where: { $0.id == id }) {
      onConfirm()
      return
    }

    guard let direction = directionsByID[id] else {
      return
    }

    if stepsByID[id] == true {
      onStep(direction)
    } else {
      onMove(direction)
    }
  }
}

/// Decodes the event before hopping to the main actor, for the same reason the
/// overlay's own hotkey does: `EventRef` and the context pointer are not
/// `Sendable`, and the controller is.
private func stepHotkeyEventHandler(
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

  guard status == noErr, pressedID.signature == stepSignature else {
    return OSStatus(eventNotHandledErr)
  }

  let controller = Unmanaged<StepHotkeyController>.fromOpaque(userData).takeUnretainedValue()
  let id = pressedID.id
  MainActor.assumeIsolated {
    controller.handleStep(id: id)
  }

  return noErr
}
