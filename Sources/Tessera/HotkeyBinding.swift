import Carbon.HIToolbox
import Foundation

/// A global hotkey, in the form Carbon needs to register it.
///
/// Parsing lives here rather than in `HotkeyController` so that a config spec can
/// be validated without touching Carbon or the event dispatcher.
struct HotkeyBinding: Equatable, Sendable {
  let modifiers: HotkeyModifiers
  let key: HotkeyKey

  var carbonKeyCode: UInt32 {
    key.carbonKeyCode
  }

  var carbonModifiers: UInt32 {
    modifiers.rawValue
  }

  /// The canonical spelling of this binding, which the config also accepts verbatim.
  var displayName: String {
    (modifiers.canonicalNames + [key.name]).joined(separator: "+")
  }

  init(modifiers: HotkeyModifiers, key: HotkeyKey) {
    self.modifiers = modifiers
    self.key = key
  }

  /// Parses a config spec such as `ctrl+alt+space`.
  ///
  /// At least one modifier is required: a bare key registered globally would
  /// swallow that key for every application on the system.
  init(parsing spec: String) throws {
    let tokens =
      spec
      .split(separator: "+", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }

    guard !tokens.contains(where: \.isEmpty) else {
      throw HotkeyBindingError.malformed(spec)
    }

    guard let keyName = tokens.last, tokens.count > 1 else {
      throw HotkeyBindingError.missingModifier(spec)
    }

    guard let key = HotkeyKey(name: keyName) else {
      throw HotkeyBindingError.unknownKey(keyName)
    }

    var modifiers: HotkeyModifiers = []
    for name in tokens.dropLast() {
      guard let modifier = HotkeyModifiers(name: name) else {
        throw HotkeyBindingError.unknownModifier(name)
      }

      modifiers.insert(modifier)
    }

    self.init(modifiers: modifiers, key: key)
  }
}

/// The four modifiers Carbon can bind, stored as Carbon's own mask.
struct HotkeyModifiers: OptionSet, Sendable {
  let rawValue: UInt32

  static let control = HotkeyModifiers(rawValue: UInt32(controlKey))
  static let option = HotkeyModifiers(rawValue: UInt32(optionKey))
  static let shift = HotkeyModifiers(rawValue: UInt32(shiftKey))
  static let command = HotkeyModifiers(rawValue: UInt32(cmdKey))

  private static let byName: [String: HotkeyModifiers] = [
    "ctrl": .control,
    "control": .control,
    "alt": .option,
    "opt": .option,
    "option": .option,
    "shift": .shift,
    "cmd": .command,
    "command": .command,
  ]

  /// A fixed order, so the same binding always logs and round-trips identically.
  var canonicalNames: [String] {
    var names: [String] = []

    if contains(.control) {
      names.append("ctrl")
    }
    if contains(.option) {
      names.append("alt")
    }
    if contains(.shift) {
      names.append("shift")
    }
    if contains(.command) {
      names.append("cmd")
    }

    return names
  }

  init(rawValue: UInt32) {
    self.rawValue = rawValue
  }

  init?(name: String) {
    guard let modifier = Self.byName[name] else {
      return nil
    }

    self = modifier
  }
}

/// A key Tessera can bind, paired with its Carbon virtual key code.
struct HotkeyKey: Equatable, Sendable {
  let name: String
  let carbonKeyCode: UInt32

  static let space = HotkeyKey(name: "space", carbonKeyCode: UInt32(kVK_Space))

  init?(name: String) {
    let canonicalName = Self.canonicalNamesByAlias[name] ?? name

    guard let carbonKeyCode = Self.carbonKeyCodesByName[canonicalName] else {
      return nil
    }

    self.init(name: canonicalName, carbonKeyCode: carbonKeyCode)
  }

  private init(name: String, carbonKeyCode: UInt32) {
    self.name = name
    self.carbonKeyCode = carbonKeyCode
  }

  /// Spelling a key two ways must produce one binding, so aliases resolve to a
  /// canonical name before lookup.
  private static let canonicalNamesByAlias: [String: String] = [
    "esc": "escape",
    "enter": "return",
  ]

  /// Virtual key codes are physical positions, not characters: `a` is the key in
  /// QWERTY's `a` position whatever the active layout prints on it.
  private static let carbonKeyCodesByName: [String: UInt32] = {
    let letters: [String: Int] = [
      "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D,
      "e": kVK_ANSI_E, "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H,
      "i": kVK_ANSI_I, "j": kVK_ANSI_J, "k": kVK_ANSI_K, "l": kVK_ANSI_L,
      "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O, "p": kVK_ANSI_P,
      "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
      "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X,
      "y": kVK_ANSI_Y, "z": kVK_ANSI_Z,
    ]

    let digits: [String: Int] = [
      "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3,
      "4": kVK_ANSI_4, "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7,
      "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    ]

    let functionKeys: [String: Int] = [
      "f1": kVK_F1, "f2": kVK_F2, "f3": kVK_F3, "f4": kVK_F4,
      "f5": kVK_F5, "f6": kVK_F6, "f7": kVK_F7, "f8": kVK_F8,
      "f9": kVK_F9, "f10": kVK_F10, "f11": kVK_F11, "f12": kVK_F12,
    ]

    let named: [String: Int] = [
      "space": kVK_Space,
      "tab": kVK_Tab,
      "return": kVK_Return,
      "escape": kVK_Escape,
      "delete": kVK_Delete,
      "left": kVK_LeftArrow,
      "right": kVK_RightArrow,
      "up": kVK_UpArrow,
      "down": kVK_DownArrow,
      "home": kVK_Home,
      "end": kVK_End,
      "pageup": kVK_PageUp,
      "pagedown": kVK_PageDown,
    ]

    return [letters, digits, functionKeys, named]
      .reduce(into: [String: Int]()) { combined, table in
        combined.merge(table) { existing, _ in existing }
      }
      .mapValues { UInt32($0) }
  }()
}

enum HotkeyBindingError: Error, Equatable, CustomStringConvertible {
  case malformed(String)
  case missingModifier(String)
  case unknownModifier(String)
  case unknownKey(String)

  var description: String {
    switch self {
    case .malformed(let spec):
      return "\"\(spec)\" is not a hotkey; expected something like ctrl+alt+space"
    case .missingModifier(let spec):
      return "hotkey \"\(spec)\" needs at least one modifier, such as ctrl, alt, shift or cmd"
    case .unknownModifier(let name):
      return "unknown hotkey modifier \"\(name)\"; expected ctrl, alt, shift or cmd"
    case .unknownKey(let name):
      return "unknown hotkey key \"\(name)\""
    }
  }
}
