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
/// it closes, so nothing outside the overlay is held: `⌃⌥⇧` with an arrow means
/// nothing to this application the rest of the time.
@MainActor
final class StepHotkeyController {
  private static let modifiers: HotkeyModifiers = [.control, .option, .shift]

  private static let directions: [(direction: OverlayGrid.Direction, key: String)] = [
    (.left, "left"), (.right, "right"), (.up, "up"), (.down, "down"),
  ]

  private let logger: AppLogger
  private let onStep: @MainActor (OverlayGrid.Direction) -> Void
  private var hotKeyRefs: [EventHotKeyRef] = []
  private var eventHandler: EventHandlerRef?
  private var directionsByID: [UInt32: OverlayGrid.Direction] = [:]

  init(debugMode: Bool, onStep: @escaping @MainActor (OverlayGrid.Direction) -> Void) {
    self.logger = AppLogger(debugMode: debugMode, category: .trigger)
    self.onStep = onStep
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

      let id = UInt32(index + 1)
      var reference: EventHotKeyRef?
      let status = RegisterEventHotKey(
        key.carbonKeyCode,
        Self.modifiers.rawValue,
        EventHotKeyID(signature: stepSignature, id: id),
        GetApplicationEventTarget(),
        0,
        &reference
      )

      guard status == noErr, let reference else {
        logger.warning("Stepping hotkey \(entry.key) refused: OSStatus \(status)")
        continue
      }

      hotKeyRefs.append(reference)
      directionsByID[id] = entry.direction
    }

    logger.debug("Holding \(hotKeyRefs.count) stepping hotkeys while the overlay is up")
  }

  func stop() {
    for reference in hotKeyRefs {
      UnregisterEventHotKey(reference)
    }

    hotKeyRefs = []
    directionsByID = [:]

    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  fileprivate func handleStep(id: UInt32) {
    guard let direction = directionsByID[id] else {
      return
    }

    onStep(direction)
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
