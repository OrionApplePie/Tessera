import Carbon.HIToolbox
import Foundation

/// Identifies this app's hotkeys in Carbon's process-wide namespace: 'TESS'.
private let hotkeySignature = OSType(0x5445_5353)

/// Owns the process-wide hotkey registration.
///
/// Carbon's `RegisterEventHotKey` is used rather than an `NSEvent` global monitor
/// because it needs no Accessibility permission and it consumes the key press
/// instead of letting it through to the focused application.
@MainActor
final class HotkeyController {
  private let binding: HotkeyBinding
  private let logger: AppLogger
  private let onTrigger: @MainActor () -> Void
  private var hotKeyRef: EventHotKeyRef?
  private var eventHandler: EventHandlerRef?

  init(
    binding: HotkeyBinding,
    debugMode: Bool,
    onTrigger: @escaping @MainActor () -> Void
  ) {
    self.binding = binding
    self.logger = AppLogger(debugMode: debugMode, category: .trigger)
    self.onTrigger = onTrigger
  }

  func start() throws {
    guard hotKeyRef == nil else {
      return
    }

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: UInt32(kEventHotKeyPressed)
    )

    let installStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      hotkeyEventHandler,
      1,
      &eventType,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )

    guard installStatus == noErr else {
      throw HotkeyError.handlerInstallFailed(status: installStatus)
    }

    let hotKeyID = EventHotKeyID(signature: hotkeySignature, id: 1)
    let registerStatus = RegisterEventHotKey(
      binding.carbonKeyCode,
      binding.carbonModifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyRef
    )

    guard registerStatus == noErr, hotKeyRef != nil else {
      stop()
      throw HotkeyError.registrationFailed(
        binding: binding.displayName,
        status: registerStatus
      )
    }

    logger.info("Registered global hotkey \(binding.displayName)")
  }

  func stop() {
    if let hotKeyRef {
      UnregisterEventHotKey(hotKeyRef)
      self.hotKeyRef = nil
      logger.info("Unregistered global hotkey \(binding.displayName)")
    }

    if let eventHandler {
      RemoveEventHandler(eventHandler)
      self.eventHandler = nil
    }
  }

  fileprivate func handleHotkeyPressed() {
    logger.debug("Global hotkey pressed \(binding.displayName)")
    onTrigger()
  }
}

/// Carbon dispatches hot key events on the main run loop, which is what makes
/// hopping onto the main actor here sound rather than a hop across threads.
///
/// The event is decoded before that hop: `EventRef` and the raw context pointer
/// are not `Sendable`, while `HotkeyController` is, being main-actor isolated.
private func hotkeyEventHandler(
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

  guard status == noErr, pressedID.signature == hotkeySignature else {
    return OSStatus(eventNotHandledErr)
  }

  let controller = Unmanaged<HotkeyController>.fromOpaque(userData).takeUnretainedValue()
  MainActor.assumeIsolated {
    controller.handleHotkeyPressed()
  }

  return noErr
}

enum HotkeyError: Error, CustomStringConvertible {
  case handlerInstallFailed(status: OSStatus)
  case registrationFailed(binding: String, status: OSStatus)

  var description: String {
    switch self {
    case .handlerInstallFailed(let status):
      return "Failed to install the global hotkey event handler: OSStatus \(status)"
    case .registrationFailed(let binding, let status):
      return
        "Failed to register the global hotkey \(binding): OSStatus \(status). "
        + "Another application probably owns it already."
    }
  }
}
