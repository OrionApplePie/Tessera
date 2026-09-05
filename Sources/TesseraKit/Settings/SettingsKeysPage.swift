import SwiftUI

// MARK: - Keys

/// The page that lists what the overlay answers to.
extension SettingsView {
  /// Every key the overlay answers to, including the two that are settings, shown
  /// as they are actually bound.
  ///
  /// Here because a switcher is used with the hands and read about once: a person
  /// who has forgotten what `⌘⏎` does will look in the window they already have
  /// open rather than in a file on disk.
  var keysPage: some View {
    Form {
      Section("Opening it") {
        key(model.hotkey.isEmpty ? "not set" : model.hotkey, "Show the map")
        key("⌃⌥ + arrows", "Step through windows, and switch when the keys are let go")
      }

      Section("Choosing") {
        key("arrows", "Move the highlight")
        key("1 – 9", "Pick that tile")
        key(
          model.overlaySearch == .fuzzy ? "any letters" : "a letter",
          model.overlaySearch == .fuzzy
            ? "Search as you type; Backspace takes a letter back"
            : "Walk the windows whose name starts with it")
        key("Tab, ⇧Tab", "The next and previous window inside a Space")
        key("Return, Space", "Switch to what the highlight is on")
        key("Esc", "Clear what was typed, then close the map")
      }

      Section("Doing something to a window") {
        key("⌘ + arrows", "Send it to the display that way")
        key("⌥ + arrows", "Put it in that half of its screen")
        key("⌘⏎", "Fill the screen with it")
        key("⌘F", "Hand it to the application's own fullscreen")
        key("⇧ + arrows", "Move the tile itself, within its group")
        key("⌃⌥⇧ + arrows", "Switch to the window that way, keeping the map up")
        key(
          model.closeHotkey.isEmpty ? "not set" : model.closeHotkey,
          model.closeAction == .quitApplication
            ? "Quit the application the window belongs to"
            : "Close the window")
      }

      Section("Spaces") {
        key("⌘N", "Add a desktop to the display the highlight is on")
        key("⌘⌫", "Close the highlighted empty Space")
      }

      Section("Whatever is playing") {
        key("⌘\\", "Play or pause it")
        key("⌘]", "Next")
        key("⌘[", "Previous")
      }
    }
  }

  /// One key and what it does. The key sits first and in one width, so the column
  /// reads as a list of keys rather than as sentences that happen to start with one.
  func key(_ combination: String, _ meaning: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(combination)
        .font(.system(size: 12, weight: .medium, design: .monospaced))
        .frame(width: 110, alignment: .leading)

      Text(meaning)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Spacer(minLength: 0)
    }
  }
}
