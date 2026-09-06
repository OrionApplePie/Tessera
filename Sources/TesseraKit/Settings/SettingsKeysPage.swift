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
      Section(localized("Opening it")) {
        key(
          model.hotkey.isEmpty ? localized("not set") : model.hotkey, localized("Show the overlay"))
        key(
          localized("⌃⌥ + arrows"),
          localized("Step through windows, and switch when the keys are let go"))
      }

      Section(localized("Choosing")) {
        key(localized("arrows"), localized("Move the highlight"))
        key(localized("1 – 9"), localized("Pick that tile"))
        key(
          model.overlaySearch == .fuzzy ? localized("any letters") : localized("a letter"),
          model.overlaySearch == .fuzzy
            ? localized("Search as you type; Backspace takes a letter back")
            : localized("Walk the windows whose name starts with it"))
        key(localized("Tab, ⇧Tab"), localized("The next and previous window inside a Space"))
        key(localized("Return, Space"), localized("Switch to what the highlight is on"))
        key(localized("Esc"), localized("Clear what was typed, then close the overlay"))
      }

      Section(localized("Doing something to a window")) {
        key(localized("⌘ + arrows"), localized("Send it to the display that way"))
        key(localized("⌥ + arrows"), localized("Put it in that half of its screen"))
        key(localized("⌘⏎"), localized("Fill the screen with it"))
        key(localized("⌘F"), localized("Hand it to the application's own fullscreen"))
        key(localized("⇧ + arrows"), localized("Move the tile itself, within its group"))
        key(
          localized("⌃⌥⇧ + arrows"),
          localized("Switch to the window that way, keeping the overlay up"))
        key(
          model.closeHotkey.isEmpty ? localized("not set") : model.closeHotkey,
          model.closeAction == .quitApplication
            ? localized("Quit the application the window belongs to")
            : localized("Close the window"))
      }

      Section(localized("Spaces")) {
        key(localized("⌘N"), localized("Add a desktop to the display the highlight is on"))
        key(localized("⌘⌫"), localized("Close the highlighted empty Space"))
      }

      Section(localized("Whatever is playing")) {
        key(localized("⌘\\"), localized("Play or pause it"))
        key(localized("⌘]"), localized("Next"))
        key(localized("⌘["), localized("Previous"))
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
