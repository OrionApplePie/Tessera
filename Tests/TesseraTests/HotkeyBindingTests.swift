import Carbon.HIToolbox
import Testing

@testable import Tessera

@Suite("HotkeyBinding")
struct HotkeyBindingTests {
  @Test("A spec parses into the Carbon key code and modifier mask")
  func parsesIntoCarbonValues() throws {
    let binding = try HotkeyBinding(parsing: "ctrl+alt+space")

    #expect(binding.modifiers == [.control, .option])
    #expect(binding.key == HotkeyKey.space)
    #expect(binding.carbonKeyCode == UInt32(kVK_Space))
    #expect(binding.carbonModifiers == UInt32(controlKey) | UInt32(optionKey))
  }

  @Test("Case and padding around the separators do not matter")
  func toleratesCaseAndWhitespace() throws {
    let binding = try HotkeyBinding(parsing: "  CMD + Shift +  A ")

    #expect(binding.modifiers == [.command, .shift])
    #expect(binding.carbonKeyCode == UInt32(kVK_ANSI_A))
  }

  @Test("Modifier aliases name the same modifier")
  func acceptsModifierAliases() throws {
    let canonical = try HotkeyBinding(parsing: "ctrl+alt+cmd+f5")

    for spec in ["control+option+command+f5", "control+opt+cmd+f5", "ctrl+option+command+f5"] {
      #expect(try HotkeyBinding(parsing: spec) == canonical)
    }
  }

  @Test("Key aliases name the same key")
  func acceptsKeyAliases() throws {
    #expect(try HotkeyBinding(parsing: "cmd+esc") == HotkeyBinding(parsing: "cmd+escape"))
    #expect(try HotkeyBinding(parsing: "cmd+enter") == HotkeyBinding(parsing: "cmd+return"))
  }

  @Test("A repeated modifier is not a second modifier")
  func ignoresRepeatedModifiers() throws {
    #expect(try HotkeyBinding(parsing: "cmd+cmd+a") == HotkeyBinding(parsing: "cmd+a"))
  }

  @Test("Every binding spells itself the same way, whichever alias built it")
  func displayNameIsCanonical() throws {
    #expect(try HotkeyBinding(parsing: "cmd+ctrl+a").displayName == "ctrl+cmd+a")
    #expect(try HotkeyBinding(parsing: "option+CONTROL+space").displayName == "ctrl+alt+space")
    #expect(try HotkeyBinding(parsing: "shift+cmd+f12").displayName == "shift+cmd+f12")
  }

  @Test("A bare key is refused, because it would swallow that key system-wide")
  func refusesABareKey() {
    #expect(throws: HotkeyBindingError.missingModifier("space")) {
      try HotkeyBinding(parsing: "space")
    }
  }

  @Test("An unknown key is refused")
  func refusesAnUnknownKey() {
    #expect(throws: HotkeyBindingError.unknownKey("notakey")) {
      try HotkeyBinding(parsing: "cmd+notakey")
    }
  }

  @Test("An unknown modifier is refused rather than ignored")
  func refusesAnUnknownModifier() {
    #expect(throws: HotkeyBindingError.unknownModifier("hyper")) {
      try HotkeyBinding(parsing: "hyper+a")
    }
  }

  @Test("An empty component is refused")
  func refusesAnEmptyComponent() {
    #expect(throws: HotkeyBindingError.malformed("cmd++a")) {
      try HotkeyBinding(parsing: "cmd++a")
    }
    #expect(throws: HotkeyBindingError.malformed("")) {
      try HotkeyBinding(parsing: "")
    }
    #expect(throws: HotkeyBindingError.malformed("cmd+")) {
      try HotkeyBinding(parsing: "cmd+")
    }
  }

  @Test("A modifier in the key position is reported as an unknown key")
  func refusesAModifierAsTheKey() {
    #expect(throws: HotkeyBindingError.unknownKey("cmd")) {
      try HotkeyBinding(parsing: "shift+cmd")
    }
  }

  @Test("A key carries its Latin letter whatever the layout prints on it")
  func keysCarryTheirLatinLetter() {
    #expect(HotkeyKey.latinLetter(forKeyCode: UInt16(kVK_ANSI_C)) == "c")
    #expect(HotkeyKey.latinLetter(forKeyCode: UInt16(kVK_ANSI_A)) == "a")
    #expect(HotkeyKey.latinLetter(forKeyCode: UInt16(kVK_ANSI_Z)) == "z")
  }

  @Test("A key that carries no letter carries none")
  func nonLetterKeysCarryNothing() {
    #expect(HotkeyKey.latinLetter(forKeyCode: UInt16(kVK_Space)) == nil)
    #expect(HotkeyKey.latinLetter(forKeyCode: UInt16(kVK_ANSI_1)) == nil)
  }

  @Test("A key press is recognised as the binding it is")
  func matchesAKeyPress() throws {
    let binding = try HotkeyBinding(parsing: "cmd+w")

    #expect(binding.matches(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command]))
    #expect(binding.matches(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command, .capsLock]))
  }

  @Test("A different key, or different modifiers, is not the binding")
  func doesNotMatchAnythingElse() throws {
    let binding = try HotkeyBinding(parsing: "cmd+w")

    #expect(binding.matches(keyCode: UInt16(kVK_ANSI_Q), modifiers: [.command]) == false)
    #expect(binding.matches(keyCode: UInt16(kVK_ANSI_W), modifiers: []) == false)
    #expect(
      binding.matches(keyCode: UInt16(kVK_ANSI_W), modifiers: [.command, .shift]) == false)
  }

  @Test("Closing is bound to the shortcut macOS uses for it")
  func defaultCloseBinding() {
    #expect(AppConfig.default.closeHotkey?.displayName == "cmd+w")
  }

  @Test("The default binding is neither Spotlight's shortcut nor a launcher's")
  func defaultBindingAvoidsTakenShortcuts() throws {
    let hotkey = try #require(AppConfig.default.hotkey)

    #expect(hotkey.displayName == "ctrl+alt+space")
    #expect(hotkey.modifiers.contains(.control))
    #expect(hotkey.modifiers.contains(.option))
    #expect(hotkey.modifiers.contains(.command) == false)
  }
}
