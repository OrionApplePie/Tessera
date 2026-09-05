import AppKit
import Carbon.HIToolbox

final class OverlayPanel: NSPanel {
  var onSelectIndex: ((Int) -> Void)?
  var onMoveSelection: ((OverlayGrid.Direction) -> Void)?
  var onMoveTile: ((OverlayGrid.Direction) -> Void)?
  /// Sends the chosen window to the display the arrow points at.
  var onSendWindow: ((OverlayGrid.Direction) -> Void)?
  /// Puts the chosen window in the half of its screen the arrow points at.
  var onPlaceWindow: ((OverlayGrid.Direction) -> Void)?
  /// Fills the screen with the chosen window, and its fullscreen counterpart.
  var onFillScreen: (() -> Void)?
  var onFullscreen: (() -> Void)?
  /// Play, pause and step through whatever the chosen window's application is
  /// playing.
  var onMedia: ((MediaKeys.Command) -> Void)?
  var onStepAndActivate: ((OverlayGrid.Direction) -> Void)?
  /// A character typed at the map, with the Latin letter of the same key: the
  /// window may be named in either alphabet, and the search tries both.
  var onType: ((Character, Character?, [Character]) -> Void)?
  /// Backspace: the last character typed is taken back.
  var onUntype: (() -> Void)?
  /// Whether anything has been typed, which is what Escape clears before it closes
  /// the overlay.
  var isSearching: (() -> Bool)?
  var onClearSearch: (() -> Void)?
  var onCloseWindow: (() -> Void)?
  var closeHotkey: HotkeyBinding?
  var onCycleWindow: ((Bool) -> Void)?
  var onActivateSelection: (() -> Void)?
  var onDismiss: (() -> Void)?

  /// Space activates alongside Return: after ctrl+alt+space opened the overlay it
  /// is the key already under the thumb.
  private static let activationKeyCodes: Set<UInt16> = [
    UInt16(kVK_Return),
    UInt16(kVK_ANSI_KeypadEnter),
    UInt16(kVK_Space),
  ]

  private static let directionsByKeyCode: [UInt16: OverlayGrid.Direction] = [
    UInt16(kVK_LeftArrow): .left,
    UInt16(kVK_RightArrow): .right,
    UInt16(kVK_UpArrow): .up,
    UInt16(kVK_DownArrow): .down,
  ]

  override var canBecomeKey: Bool {
    true
  }

  /// A shortcut with a command or control key never reaches `keyDown`: AppKit
  /// offers it to the responder chain as a key equivalent first, and beeps if
  /// nobody claims it. Which is exactly what the first attempt at closing a window
  /// from here did.
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    if matchesCloseHotkey(event) {
      onCloseWindow?()
      return true
    }

    // A command key with a letter never reaches `keyDown`: AppKit offers it around
    // as a key equivalent first, and whoever wants it takes it there. That is the
    // only door these two have.
    guard event.modifierFlags.contains(.command) else {
      return super.performKeyEquivalent(with: event)
    }

    switch event.keyCode {
    case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter):
      onFillScreen?()
    case UInt16(kVK_ANSI_Backslash):
      onMedia?(.playPause)
    case UInt16(kVK_ANSI_RightBracket):
      onMedia?(.next)
    case UInt16(kVK_ANSI_LeftBracket):
      onMedia?(.previous)
    default:
      // The key by its place on the board, so a Russian layout finds it too — and
      // by its character as well, because a synthesized keystroke carries the
      // letter without the key it came from.
      guard
        event.keyCode == UInt16(kVK_ANSI_F)
          || event.charactersIgnoringModifiers?.lowercased() == "f"
      else {
        return super.performKeyEquivalent(with: event)
      }

      onFullscreen?()
    }

    return true
  }

  private func matchesCloseHotkey(_ event: NSEvent) -> Bool {
    closeHotkey?.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) == true
  }

  /// A character to type at the map, if that is what this is.
  ///
  /// Shift and caps lock are ignored rather than excluded: they change the letter,
  /// not the intent. Any other modifier means the key belongs to somebody else.
  private static func jumpCharacter(for event: NSEvent) -> Character? {
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.shift, .capsLock])

    guard modifiers.isEmpty, let character = event.charactersIgnoringModifiers?.first else {
      return nil
    }

    // A letter always starts a search. A digit or a space only continues one — on
    // their own they belong to picking a tile by its number.
    return character.isLetter || character.isNumber || character == " " ? character : nil
  }

  /// What an arrow does, by what is held with it. Arrow keys always carry the
  /// function and numeric pad flags, so those are taken out before anything is
  /// compared: what is left is what a person actually held.
  private func arrow(_ direction: OverlayGrid.Direction, held flags: NSEvent.ModifierFlags) {
    let modifiers =
      flags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .function, .numericPad])

    switch modifiers {
    case [.shift]:
      onMoveTile?(direction)
    case [.command]:
      onSendWindow?(direction)
    case [.option]:
      onPlaceWindow?(direction)
    case [.control, .option], [.control, .option, .shift]:
      onStepAndActivate?(direction)
    default:
      onMoveSelection?(direction)
    }
  }

  /// The two keys that take something back: Escape drops what was typed before it
  /// drops the overlay, and Backspace drops the last character of it. Says whether
  /// it took the key.
  private func escapeOrBackspace(_ event: NSEvent) -> Bool {
    if event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1b}" {
      // What was typed goes first, and the overlay only on a second press: escaping
      // a search that has gone wrong should not also lose the map.
      if isSearching?() == true {
        onClearSearch?()
      } else {
        onDismiss?()
      }

      return true
    }

    guard event.keyCode == UInt16(kVK_Delete) else {
      return false
    }

    onUntype?()

    return true
  }

  override func keyDown(with event: NSEvent) {
    if escapeOrBackspace(event) {
      return
    }

    if let direction = Self.directionsByKeyCode[event.keyCode] {
      arrow(direction, held: event.modifierFlags)
      return
    }

    if event.keyCode == UInt16(kVK_Tab) {
      onCycleWindow?(!event.modifierFlags.contains(.shift))
      return
    }

    if Self.activationKeyCodes.contains(event.keyCode) {
      // Space is a letter while something is being typed — "microsoft word" has one
      // in it — and the key that says "this one" the rest of the time. Return always
      // says "this one".
      if event.keyCode == UInt16(kVK_Space), isSearching?() == true {
        onType?(" ", " ", [" "])
      } else {
        onActivateSelection?()
      }

      return
    }

    // A digit picks a tile outright — until something has been typed, when it is
    // part of what is being typed instead: "desktop 3" has to be able to reach the
    // third desktop.
    let digit = event.charactersIgnoringModifiers.flatMap { Int($0) }
    if let digit, (1...9).contains(digit), isSearching?() != true {
      onSelectIndex?(digit - 1)
      return
    }

    // A binding without a command or control key arrives here rather than as a key
    // equivalent, so both doors are watched.
    if matchesCloseHotkey(event) {
      onCloseWindow?()
      return
    }

    if let character = Self.jumpCharacter(for: event) {
      // A letter starts a search; a digit only continues one, since on its own it
      // picks a tile by its number.
      guard character.isLetter || isSearching?() == true else {
        return
      }

      onType?(
        character,
        HotkeyKey.latinLetter(forKeyCode: event.keyCode),
        KeyboardLayouts.readings(
          typed: character,
          latin: HotkeyKey.latinLetter(forKeyCode: event.keyCode),
          onOtherLayouts: KeyboardLayouts.characters(forKeyCode: event.keyCode)
        )
      )
      return
    }

    super.keyDown(with: event)
  }
}
