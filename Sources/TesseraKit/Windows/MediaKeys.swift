import AppKit
import CoreGraphics

/// The play, next and previous keys, as the keyboard sends them.
///
/// Not a private framework: these are ordinary system-defined events, the same
/// ones a keyboard with media keys puts out, and macOS routes them to whatever it
/// considers the application that is playing. Reading *what* is playing needs an
/// entitlement Apple stopped giving out in macOS 15.4; sending these does not.
///
/// Which application hears them is therefore the system's decision, not ours. With
/// one thing playing — the case this exists for — it is the thing playing.
enum MediaKeys {
  enum Command {
    case playPause
    case next
    case previous

    /// The codes in the auxiliary keyboard, which is where the media keys live.
    fileprivate var key: Int32 {
      switch self {
      case .playPause:
        return NX_KEYTYPE_PLAY
      case .next:
        return NX_KEYTYPE_NEXT
      case .previous:
        return NX_KEYTYPE_PREVIOUS
      }
    }
  }

  /// Sends one command, down and up. Says whether both events could be made.
  @discardableResult
  static func send(_ command: Command) -> Bool {
    press(command.key, isDown: true) && press(command.key, isDown: false)
  }

  /// A media key is not a key press but a system-defined event carrying the key in
  /// its data, which is why this cannot go through `CGEvent(keyboardEventSource:)`.
  private static func press(_ key: Int32, isDown: Bool) -> Bool {
    let data = Int((key << 16) | ((isDown ? 0x0A : 0x0B) << 8))

    guard
      let event = NSEvent.otherEvent(
        with: .systemDefined,
        location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: isDown ? 0xA00 : 0xB00),
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        subtype: 8,
        data1: data,
        data2: -1
      ),
      let posted = event.cgEvent
    else {
      return false
    }

    posted.post(tap: .cghidEventTap)

    return true
  }
}
