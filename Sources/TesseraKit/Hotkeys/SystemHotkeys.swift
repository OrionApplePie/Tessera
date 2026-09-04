import AppKit
import Foundation

/// A keyboard shortcut macOS itself owns.
///
/// Binding the same combination as a system shortcut is not an error and nothing
/// reports it: `RegisterEventHotKey` returns `noErr`, both registrations stand,
/// and the key press goes to whichever of the two registered last. The overlay
/// therefore opens for hours and then quietly stops, with a live registration and
/// an empty log — which is exactly how this was found.
///
/// The combination Tessera shipped as its default, ctrl+alt+space, is also
/// "Select the next source in the Input menu" on every Mac with a second keyboard
/// layout, so this is not a rare collision.
struct SystemHotkey: Equatable, Sendable {
  let id: Int
  let keyCode: UInt32
  let modifiers: HotkeyModifiers

  /// What System Settings calls this shortcut, for the ones worth naming. An
  /// unnamed one still identifies itself by number, which is enough to find it.
  var name: String {
    Self.namesByID[id] ?? String(localized: "a macOS shortcut (id \(id))")
  }

  private static let namesByID: [Int: String] = [
    32: String(localized: "Mission Control"),
    33: String(localized: "Application windows"),
    60: String(localized: "Select the previous input source"),
    61: String(localized: "Select the next source in the Input menu"),
    64: String(localized: "Show Spotlight search"),
    65: String(localized: "Show Spotlight file window"),
    79: String(localized: "Move left a space"),
    81: String(localized: "Move right a space"),
  ]
}

/// Reads the shortcuts macOS has assigned to itself.
///
/// There is no API for this — the shortcuts live in a preference domain, one
/// entry per shortcut, each holding whether it is enabled and three parameters:
/// the character, the virtual key code, and the modifiers as a Cocoa mask.
/// Reading a plist is public in a way that the undeclared `CopySymbolicHotKeys`
/// symbol is not, and it needs no permission.
enum SystemHotkeys {
  static let preferenceDomain = "com.apple.symbolichotkeys"
  static let preferenceKey = "AppleSymbolicHotKeys"

  static func enabled() -> [SystemHotkey] {
    guard
      let defaults = UserDefaults(suiteName: preferenceDomain),
      let raw = defaults.dictionary(forKey: preferenceKey)
    else {
      return []
    }

    return parse(raw)
  }

  /// The enabled shortcuts in a `AppleSymbolicHotKeys` dictionary.
  ///
  /// An entry that does not parse is skipped rather than failing the read: this
  /// is someone else's preference file, it holds entries of several shapes, and a
  /// shortcut we cannot read is one we simply cannot warn about.
  static func parse(_ raw: [String: Any]) -> [SystemHotkey] {
    raw.compactMap { key, value in
      guard
        let id = Int(key),
        let entry = value as? [String: Any],
        let enabled = entry["enabled"] as? Bool, enabled,
        let container = entry["value"] as? [String: Any],
        let parameters = container["parameters"] as? [Int],
        parameters.count >= 3
      else {
        return nil
      }

      // 65535 stands in for "no key" in entries bound to a mouse button or to a
      // modifier alone; a real virtual key code is a byte.
      let keyCode = parameters[1]
      guard (0..<0x80).contains(keyCode) else {
        return nil
      }

      return SystemHotkey(
        id: id,
        keyCode: UInt32(keyCode),
        modifiers: HotkeyModifiers(NSEvent.ModifierFlags(rawValue: UInt(parameters[2])))
      )
    }
    .sorted { $0.id < $1.id }
  }

  static func conflict(
    with binding: HotkeyBinding,
    among hotkeys: [SystemHotkey] = enabled()
  ) -> SystemHotkey? {
    hotkeys.first { $0.keyCode == binding.carbonKeyCode && $0.modifiers == binding.modifiers }
  }
}
