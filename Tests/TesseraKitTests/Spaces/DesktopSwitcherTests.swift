import Carbon.HIToolbox
import Foundation
import Testing

@testable import TesseraKit

@Suite("DesktopSwitcher")
struct DesktopSwitcherTests {
  /// What a live `com.apple.symbolichotkeys` holds for the desktop shortcuts:
  /// ⌃1 through ⌃4 at 118…121, then the rest, all of them plain control plus a
  /// digit.
  private static func desktopHotkeys(_ numbers: ClosedRange<Int>) -> [SystemHotkey] {
    let keyCodes: [UInt32] = [18, 19, 20, 21, 23, 22, 26, 28]

    return numbers.map { number in
      SystemHotkey(
        id: DesktopSwitcher.firstSymbolicID + number - 1,
        keyCode: keyCodes[number - 1],
        modifiers: .control
      )
    }
  }

  @Test("finds the shortcut macOS binds to a desktop")
  func findsTheShortcut() {
    let found = DesktopSwitcher.shortcut(forDesktop: 3, among: Self.desktopHotkeys(1...4))

    #expect(found?.id == 120)
    #expect(found?.keyCode == 20)
    #expect(found?.modifiers == .control)
  }

  /// The user's to switch off, and `SystemHotkeys.enabled()` returns only the ones
  /// still on — so a desktop whose shortcut is gone has no way in, and saying so
  /// is what stops the overlay claiming a switch that never happened.
  @Test("has no answer for a desktop whose shortcut is switched off")
  func missingShortcut() {
    let found = DesktopSwitcher.shortcut(forDesktop: 5, among: Self.desktopHotkeys(1...4))

    #expect(found == nil)
  }

  @Test("has no answer past the last desktop macOS binds")
  func pastTheLastDesktop() {
    let hotkeys = Self.desktopHotkeys(1...8)

    #expect(DesktopSwitcher.shortcut(forDesktop: 9, among: hotkeys) == nil)
    #expect(DesktopSwitcher.shortcut(forDesktop: 0, among: hotkeys) == nil)
  }
}

@Suite("SpaceQuery desktop numbers")
struct SpaceQueryNumberingTests {
  private func desktop(_ id: Int) -> SpaceQuery.Space {
    SpaceQuery.Space(id: id, isFullscreen: false)
  }

  private func fullscreen(_ id: Int) -> SpaceQuery.Space {
    SpaceQuery.Space(id: id, isFullscreen: true)
  }

  /// Measured on this machine: the built-in display holds desktops 3 and 4108 plus
  /// three fullscreen Spaces, the external one holds a single desktop 4556 — and
  /// that one answers to ⌃3, not to ⌃1. The count runs across displays and skips
  /// fullscreen Spaces, which macOS does not number.
  @Test("numbers desktops across displays, skipping fullscreen Spaces")
  func numbersAcrossDisplays() {
    let numbers = SpaceQuery.desktopNumbers(inOrder: [
      [desktop(3), desktop(4108), fullscreen(4399), fullscreen(4432), fullscreen(5799)],
      [fullscreen(4351), desktop(4556), fullscreen(5847), fullscreen(5870)],
    ])

    #expect(numbers[3] == 1)
    #expect(numbers[4108] == 2)
    #expect(numbers[4556] == 3)
  }

  @Test("gives a fullscreen Space no number")
  func fullscreenHasNoNumber() {
    let numbers = SpaceQuery.desktopNumbers(inOrder: [[desktop(3), fullscreen(4399)]])

    #expect(numbers[4399] == nil)
    #expect(numbers.count == 1)
  }

  @Test("says nothing when the window server said nothing")
  func noDisplays() {
    #expect(SpaceQuery.desktopNumbers(inOrder: []).isEmpty)
  }
}

/// Where the click that moves the attention to a display lands.
@Suite("Clicking a menu bar")
struct MenuBarPointTests {
  /// The bug this is for: a third of the way into a laptop's bar is where Finder's
  /// "Window" menu sits, and the click opened the menu instead of moving anything.
  @Test("The click goes past the menus, with room to spare")
  func clearsTheMenus() {
    #expect(DesktopSwitcher.pointPastMenus(endingAt: 606, barWidth: 1512) == 630)
    #expect(DesktopSwitcher.pointPastMenus(endingAt: 400, barWidth: 1512) == 424)
  }

  /// An application reporting almost no menus is not taken at its word: the bar
  /// belongs to whatever is in front, and that can change between the asking and
  /// the clicking.
  @Test("It never lands in the first fifth of the bar")
  func staysOutOfTheMenusAnyway() {
    #expect(DesktopSwitcher.pointPastMenus(endingAt: 0, barWidth: 1512) == 1512 * 0.2)
    #expect(DesktopSwitcher.pointPastMenus(endingAt: 100, barWidth: 2560) == 2560 * 0.2)
  }

  /// The right end of a bar is status items, and clicking one of those opens it.
  @Test("It never reaches the status items")
  func staysOutOfTheStatusItems() {
    #expect(DesktopSwitcher.pointPastMenus(endingAt: 1400, barWidth: 1512) == 1512 * 0.75)
  }
}
