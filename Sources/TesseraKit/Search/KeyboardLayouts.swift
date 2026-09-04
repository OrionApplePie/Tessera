import Carbon.HIToolbox
import Foundation

/// What a physical key says, on every keyboard layout the machine has enabled.
///
/// A key press is a position on the keyboard plus whatever the layout in use makes
/// of it. With a Latin layout active that is "v", and no window called
/// "Мониторинг системы" starts with a "v" — so the letter jump could not reach a
/// Russian title at all without switching layout first. Measured: on ABC, pressing
/// the key that carries "м" left the selection where it was.
///
/// macOS will translate a key code through any installed layout, so a key can mean
/// everything printed on it at once: "v" and "м" together. Two layouts cost 16µs
/// per press, which is why none of this is cached — a layout added while the app
/// runs is picked up on the next key press rather than on the next launch.
enum KeyboardLayouts {
  /// The letters `keyCode` produces across the enabled keyboard layouts.
  ///
  /// Input methods that translate rather than map keys — the Chinese and Japanese
  /// sources, among others — publish no key layout, and are skipped. A key that
  /// produces something other than a letter is skipped too: the jump matches the
  /// first letter of a name, and punctuation is never that.
  static func characters(forKeyCode keyCode: UInt16) -> [Character] {
    let filter = [kTISPropertyInputSourceCategory: kTISCategoryKeyboardInputSource] as CFDictionary

    guard
      let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue()
        as? [TISInputSource]
    else {
      return []
    }

    return sources.compactMap { letter(keyCode, from: $0) }
  }

  /// The readings of one key press, in the order they are worth trying: what was
  /// typed, then the Latin letter of the same key, then what other layouts make of
  /// it. A reading already in the list is dropped, ignoring case, so pressing a
  /// letter walks its windows once rather than twice.
  static func readings(
    typed: Character,
    latin: Character?,
    onOtherLayouts others: [Character]
  ) -> [Character] {
    var readings: [Character] = []
    var seen: Set<String> = []

    for character in [typed] + [latin].compactMap({ $0 }) + others
    where seen.insert(String(character).lowercased()).inserted {
      readings.append(character)
    }

    return readings
  }

  private static func letter(_ keyCode: UInt16, from source: TISInputSource) -> Character? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
      return nil
    }

    let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data

    return data.withUnsafeBytes { buffer -> Character? in
      guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
        return nil
      }

      var deadKeyState: UInt32 = 0
      var length = 0
      var characters = [UniChar](repeating: 0, count: 4)
      let status = UCKeyTranslate(
        layout,
        keyCode,
        UInt16(kUCKeyActionDown),
        0,
        UInt32(LMGetKbdType()),
        OptionBits(kUCKeyTranslateNoDeadKeysBit),
        &deadKeyState,
        characters.count,
        &length,
        &characters
      )

      guard status == noErr, length > 0,
        let character = String(utf16CodeUnits: characters, count: length).first,
        character.isLetter
      else {
        return nil
      }

      return character
    }
  }
}
