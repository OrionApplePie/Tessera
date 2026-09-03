import AppKit
import Carbon.HIToolbox

final class OverlayPanel: NSPanel {
  var onSelectIndex: ((Int) -> Void)?
  var onMoveSelection: ((OverlayGrid.Direction) -> Void)?
  var onMoveTile: ((OverlayGrid.Direction) -> Void)?
  var onStepAndActivate: ((OverlayGrid.Direction) -> Void)?
  var onJumpToName: (([Character]) -> Void)?
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
    guard matchesCloseHotkey(event) else {
      return super.performKeyEquivalent(with: event)
    }

    onCloseWindow?()
    return true
  }

  private func matchesCloseHotkey(_ event: NSEvent) -> Bool {
    closeHotkey?.matches(keyCode: event.keyCode, modifiers: event.modifierFlags) == true
  }

  /// A bare letter, if that is what this is.
  ///
  /// Shift and caps lock are ignored rather than excluded: they change the letter,
  /// not the intent. Any other modifier means the key belongs to somebody else.
  private static func jumpCharacter(for event: NSEvent) -> Character? {
    let modifiers = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.shift, .capsLock])

    guard modifiers.isEmpty,
      let character = event.charactersIgnoringModifiers?.first,
      character.isLetter
    else {
      return nil
    }

    return character
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == UInt16(kVK_Escape) || event.charactersIgnoringModifiers == "\u{1b}" {
      onDismiss?()
      return
    }

    if let direction = Self.directionsByKeyCode[event.keyCode] {
      // Arrow keys always carry the function and numeric pad flags, so only shift
      // distinguishes moving a tile from moving the highlight.
      let modifiers = event.modifierFlags
        .intersection(.deviceIndependentFlagsMask)
        .subtracting([.capsLock, .function, .numericPad])

      switch modifiers {
      case [.shift]:
        onMoveTile?(direction)
      case [.control, .option], [.control, .option, .shift]:
        onStepAndActivate?(direction)
      default:
        onMoveSelection?(direction)
      }

      return
    }

    if event.keyCode == UInt16(kVK_Tab) {
      onCycleWindow?(!event.modifierFlags.contains(.shift))
      return
    }

    if Self.activationKeyCodes.contains(event.keyCode) {
      onActivateSelection?()
      return
    }

    let digit = event.charactersIgnoringModifiers.flatMap { Int($0) }
    if let digit, (1...9).contains(digit) {
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
      onJumpToName?(
        KeyboardLayouts.readings(
          typed: character,
          latin: HotkeyKey.latinLetter(forKeyCode: event.keyCode),
          onOtherLayouts: KeyboardLayouts.characters(forKeyCode: event.keyCode)
        ))
      return
    }

    super.keyDown(with: event)
  }
}
