import Carbon.HIToolbox
import Foundation
import Testing

@testable import TesseraKit

@Suite("SystemHotkeys")
struct SystemHotkeysTests {
  /// The shape macOS actually writes, taken from a live `com.apple.symbolichotkeys`:
  /// 60 and 61 switch input source, 61 being ctrl+alt+space, and 175 is bound to
  /// no key at all.
  private static let realPreferences = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>60</key>
      <dict>
        <key>enabled</key><true/>
        <key>value</key>
        <dict>
          <key>parameters</key>
          <array><integer>32</integer><integer>49</integer><integer>262144</integer></array>
          <key>type</key><string>standard</string>
        </dict>
      </dict>
      <key>61</key>
      <dict>
        <key>enabled</key><true/>
        <key>value</key>
        <dict>
          <key>parameters</key>
          <array><integer>32</integer><integer>49</integer><integer>786432</integer></array>
          <key>type</key><string>standard</string>
        </dict>
      </dict>
      <key>175</key>
      <dict>
        <key>enabled</key><true/>
        <key>value</key>
        <dict>
          <key>parameters</key>
          <array><integer>65535</integer><integer>65535</integer><integer>0</integer></array>
          <key>type</key><string>standard</string>
        </dict>
      </dict>
    </dict>
    </plist>
    """

  private static func parseRealPreferences() throws -> [SystemHotkey] {
    let data = try #require(realPreferences.data(using: .utf8))
    let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
    let raw = try #require(plist as? [String: Any])

    return SystemHotkeys.parse(raw)
  }

  @Test("A live preference file parses into key codes and modifiers")
  func parsesTheShapeMacOSWrites() throws {
    let hotkeys = try Self.parseRealPreferences()

    #expect(hotkeys.map(\.id) == [60, 61])
    #expect(hotkeys[1].keyCode == UInt32(kVK_Space))
    #expect(hotkeys[1].modifiers == [.control, .option])
  }

  @Test("A shortcut bound to no key is left out")
  func skipsEntriesWithoutAKey() throws {
    let hotkeys = try Self.parseRealPreferences()

    #expect(!hotkeys.contains { $0.id == 175 })
  }

  @Test("A switched-off shortcut claims nothing")
  func skipsDisabledEntries() {
    let raw: [String: Any] = [
      "61": [
        "enabled": false,
        "value": ["parameters": [32, 49, 786432], "type": "standard"],
      ]
    ]

    #expect(SystemHotkeys.parse(raw).isEmpty)
  }

  @Test("An entry that does not parse does not discard the rest of the file")
  func skipsMalformedEntries() {
    let raw: [String: Any] = [
      "not a number": ["enabled": true],
      "60": ["enabled": true, "value": ["parameters": [32]]],
      "61": [
        "enabled": true,
        "value": ["parameters": [32, 49, 786432], "type": "standard"],
      ],
    ]

    #expect(SystemHotkeys.parse(raw).map(\.id) == [61])
  }

  @Test("The hotkey Tessera shipped as its default collides with the input menu")
  func reportsTheCollision() throws {
    let hotkeys = try Self.parseRealPreferences()
    let binding = try HotkeyBinding(parsing: "ctrl+alt+space")

    let conflict = try #require(SystemHotkeys.conflict(with: binding, among: hotkeys))
    #expect(conflict.id == 61)
    // Named in whatever language the switcher is speaking, so the name is compared
    // against the same table rather than against English.
    #expect(conflict.name == localized("Select the next source in the Input menu"))
  }

  @Test("A binding macOS does not claim reports nothing")
  func reportsNoCollisionForAFreeBinding() throws {
    let hotkeys = try Self.parseRealPreferences()
    let binding = try HotkeyBinding(parsing: "alt+tab")

    #expect(SystemHotkeys.conflict(with: binding, among: hotkeys) == nil)
  }

  @Test("The same key with other modifiers is a different shortcut")
  func distinguishesModifiers() throws {
    let hotkeys = try Self.parseRealPreferences()
    let binding = try HotkeyBinding(parsing: "ctrl+shift+space")

    #expect(SystemHotkeys.conflict(with: binding, among: hotkeys) == nil)
  }

  @Test("A shortcut with no name still identifies itself")
  func namesUnknownShortcutsByID() {
    let hotkey = SystemHotkey(id: 999, keyCode: 49, modifiers: [.control])

    // What matters is that a shortcut nobody has a name for still says which one it
    // is; the sentence around the number is a translated string.
    #expect(hotkey.name.contains("999"))
    #expect(hotkey.name == localized("a macOS shortcut (id %lld)", 999))
  }
}
