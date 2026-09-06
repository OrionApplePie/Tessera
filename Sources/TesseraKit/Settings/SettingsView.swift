import SwiftUI

/// A page of the settings window, and the list on its left.
enum SettingsSection: String, CaseIterable, Identifiable {
  case app
  case layout
  case appearance
  case timing
  case keys
  case about

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .app:
      return localized("App")
    case .layout:
      return localized("Layout")
    case .appearance:
      return localized("Appearance")
    case .timing:
      return localized("Timing")
    case .keys:
      return localized("Keys")
    case .about:
      return localized("About")
    }
  }

  var symbol: String {
    switch self {
    case .app:
      return "gearshape"
    case .layout:
      return "square.grid.2x2"
    case .appearance:
      return "paintpalette"
    case .timing:
      return "timer"
    case .keys:
      return "keyboard"
    case .about:
      return "info.circle"
    }
  }
}

/// The settings window's contents.
///
/// Saving writes the file and restarts the background app, because the
/// configuration is read once at launch and handed to the services as values.
/// Applying it live would mean making it a shared, observed source instead, which
/// is a change to how the whole app is wired rather than a change to this window.
struct SettingsView: View {
  @ObservedObject var model: SettingsModel
  let onSave: () -> Void
  let onCancel: () -> Void

  @State private var section: SettingsSection

  /// Set while the window is being sized. A `Form` is a scroll view, and a scroll
  /// view's fitting size is the least it can be squeezed to, not the height of what
  /// it holds — measuring one gives a window that is too short by however much the
  /// longest page would have scrolled. Fixing the vertical size for the measurement
  /// makes the page report what it actually draws.
  private let isMeasuring: Bool

  /// The section is a parameter so that each page can be measured on its own when
  /// the window is sized, not because anything else opens on a page but the first.
  init(
    model: SettingsModel,
    section: SettingsSection = .app,
    measuring: Bool = false,
    onSave: @escaping () -> Void,
    onCancel: @escaping () -> Void
  ) {
    self.model = model
    self.isMeasuring = measuring
    self.onSave = onSave
    self.onCancel = onCancel
    _section = State(initialValue: section)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        List(SettingsSection.allCases, selection: $section) { section in
          Label(section.title, systemImage: section.symbol)
            .tag(section)
        }
        .listStyle(.sidebar)
        .frame(width: 150)

        Divider()

        page
          .formStyle(.grouped)
          .fixedSize(horizontal: false, vertical: isMeasuring)
          .frame(maxWidth: .infinity, maxHeight: isMeasuring ? nil : .infinity)
      }

      Divider()
      footer
    }
    // Landscape: a list of sections down the side and one page beside it, rather
    // than one long column that has to be scrolled past what you are not editing.
    //
    // Width only. An ideal height here is what the window would be measured as
    // whatever the page holds, which is how the longest page ended up with a scroll
    // bar: the height is the window's business, and it takes it from the pages.
    .frame(minWidth: 560, idealWidth: 560)
  }

  @ViewBuilder
  private var page: some View {
    switch section {
    case .app:
      appPage
    case .layout:
      layoutPage
    case .appearance:
      appearancePage
    case .timing:
      timingPage
    case .keys:
      keysPage
    case .about:
      aboutPage
    }
  }

  /// How the overlay looks, and what its tiles show.
  private var appearancePage: some View {
    Form {
      Section(localized("Surface")) {
        ColorPicker(localized("Background"), selection: $model.background, supportsOpacity: true)
      }

      Section(localized("Tiles")) {
        Picker(localized("Show"), selection: $model.thumbnailMode) {
          Text(localized("The whole window")).tag(WindowThumbnailMode.fit)
          Text(localized("Its corner, at actual size")).tag(WindowThumbnailMode.corner)
          Text(localized("Its corner, twice as much")).tag(WindowThumbnailMode.cornerDouble)
          Text(localized("Roughly a quarter of it")).tag(WindowThumbnailMode.quarter)
          Text(localized("Three quarters of it")).tag(WindowThumbnailMode.threeQuarters)
        }

        Picker(localized("Capture at"), selection: $model.thumbnailQuality) {
          Text(localized("What the tile shows")).tag(ThumbnailQuality.tile)
          Text(localized("HD, sharper and heavier")).tag(ThumbnailQuality.hd)
          Text(localized("The most, and the most memory")).tag(ThumbnailQuality.max)
        }

        Toggle(
          localized("A long window whole, whatever the mode"),
          isOn: $model.capturesLongWindowsWhole)

        Toggle(localized("Fade a stale preview"), isOn: $model.dimsStaleThumbnails)
      }
    }
  }

  /// The shape of the map: how many Spaces stand where, how large they are drawn,
  /// and what a keypress moves through.
  private var layoutPage: some View {
    Form {
      Section(localized("The overlay")) {
        // First, because it decides whether anything below it is listened to. With
        // it off the map is drawn at a fixed tile size and the row length is the
        // only thing that shapes it; with it on the arrangement chooses, and works
        // the row length out for itself unless it is the fixed one.
        Toggle(localized("Grow the overlay into the screen"), isOn: $model.overlayFillsScreen)

        Picker(localized("Arrange"), selection: $model.overlayLayout) {
          Text(localized("As large as the screen allows")).tag(OverlayLayout.fitted)
          Text(localized("A fixed number across")).tag(OverlayLayout.rows)
          Text(localized("A square, by how many there are")).tag(OverlayLayout.count)
          Text(localized("One after another, wrapping")).tag(OverlayLayout.flow)
        }
        .disabled(!model.overlayFillsScreen)

        Stepper(value: $model.overlayColumns, in: 1...12) {
          setting(localized("Spaces across"), "\(model.overlayColumns)")
        }
        .disabled(model.overlayFillsScreen && model.overlayLayout != .rows)

        Stepper(value: $model.overlayMaxCells, in: 1...60) {
          setting(localized("At most"), localized("%lld Spaces", model.overlayMaxCells))
        }

        Stepper(value: $model.overlayMinTile, in: 90...400, step: 10) {
          setting(localized("Smallest tile"), localized("%lld pt", Int(model.overlayMinTile)))
        }

        Text(gridNote)
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker(localized("Short rows sit"), selection: $model.overlayRowAlignment) {
          Text(localized("In the middle")).tag(OverlayRowAlignment.center)
          Text(localized("To the left")).tag(OverlayRowAlignment.leading)
          Text(localized("To the right")).tag(OverlayRowAlignment.trailing)
        }
      }

      Section(localized("Groups")) {
        Picker(localized("A Space of several windows"), selection: $model.overlayDeck) {
          Text(localized("One tile, flipped through")).tag(OverlayDeckStyle.stack)
          Text(localized("Tiles fanned out")).tag(OverlayDeckStyle.fan)
          Text(localized("One tile, dealt in place")).tag(OverlayDeckStyle.deal)
        }

        Toggle(localized("Group by display"), isOn: $model.groupsDisplays)
        Toggle(localized("Group by Space"), isOn: $model.groupsSpaces)
      }

      Section(localized("Order")) {
        Picker(localized("Arrows move by"), selection: $model.overlayArrows) {
          Text(localized("Space, Tab for its windows")).tag(OverlayArrowStep.spaces)
          Text(localized("Window")).tag(OverlayArrowStep.windows)
        }

        Picker(localized("Typing a letter"), selection: $model.overlaySearch) {
          Text(localized("Walks the windows of that name")).tag(OverlaySearch.letter)
          Text(localized("Searches, letter by letter")).tag(OverlaySearch.fuzzy)
        }

        Picker(localized("Windows in a group"), selection: $model.windowOrder) {
          Text(localized("Application and title")).tag(WindowOrder.title)
          Text(localized("Application only")).tag(WindowOrder.application)
          Text(localized("Never reorder")).tag(WindowOrder.stable)
        }
      }
    }
  }

  /// Everything the switcher waits for. Each of these is a compromise measured on
  /// a real desktop rather than a value with a right answer, so each is here.
  private var timingPage: some View {
    Form {
      Section(localized("Refresh")) {
        Stepper(value: $model.refreshIntervalSeconds, in: 0.5...60, step: 0.5) {
          setting(localized("Every"), seconds(model.refreshIntervalSeconds))
        }

        Stepper(value: $model.windowThumbnailsStaleSeconds, in: 1...600, step: 5) {
          setting(localized("Stale after"), seconds(model.windowThumbnailsStaleSeconds))
        }
      }

      Section(localized("Reaching a window")) {
        Stepper(value: $model.activationSettleSeconds, in: 0.5...10, step: 0.5) {
          setting(localized("Let the system settle for"), seconds(model.activationSettleSeconds))
        }
      }

      Section(localized("Waiting for an answer")) {
        Stepper(value: $model.unresponsiveAfterSeconds, in: 0.5...30, step: 0.5) {
          setting(localized("Wedged after"), seconds(model.unresponsiveAfterSeconds))
        }
      }
    }
  }

  private var appPage: some View {
    Form {
      Section(localized("Shortcut")) {
        TextField(
          localized("Show the overlay"), text: $model.hotkey,
          prompt: Text(localized("ctrl+alt+space")))

        TextField(
          localized("Close a window"), text: $model.closeHotkey, prompt: Text(localized("cmd+w")))

        Picker(localized("Closing"), selection: $model.closeAction) {
          Text(localized("Closes the window")).tag(CloseAction.closeWindow)
          Text(localized("Quits the application")).tag(CloseAction.quitApplication)
        }
      }

      Section(localized("Windows")) {
        TextField(
          localized("Ignore applications"),
          text: $model.ignoredApplications,
          prompt: Text(localized("AmneziaVPN, Some Tray App"))
        )
        Stepper(value: $model.maxWindows, in: 1...96) {
          setting(localized("Never list more than"), localized("%lld windows", model.maxWindows))
        }

        Text(windowsNote)
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle(localized("Close the overlay after switching"), isOn: $model.closeAfterActivation)
        Toggle(
          localized("Leave out menu bar applications"), isOn: $model.ignoresMenuBarApplications)
      }

      Section(localized("The switcher itself")) {
        Toggle(
          localized("Ask the window server which Space a window is on"),
          isOn: $model.usesPrivateSpaceAPI)
        Toggle(localized("Show the menu bar icon"), isOn: $model.showMenuBarIcon)
        Toggle(localized("Verbose logging"), isOn: $model.debugMode)
      }
    }
  }

  private var footer: some View {
    HStack {
      if let problem = model.problem {
        Text(problem)
          .font(.callout)
          .foregroundStyle(.red)
          .lineLimit(2)
      }

      Spacer()

      // Fills the form and stops there: nothing is written until Save, so the
      // defaults can be read off the pages first, and Cancel is still a way out.
      Button(localized("Restore Defaults")) {
        model.restoreDefaults()
      }

      Button(localized("Cancel"), action: onCancel)
        .keyboardShortcut(.cancelAction)
      Button(localized("Save and Restart"), action: onSave)
        .keyboardShortcut(.defaultAction)
    }
    .padding(16)
  }

  /// A setting's name and its value, with the value pushed to the right so that it
  /// sits beside the buttons that change it rather than at the far end of a
  /// sentence. Digits of even width, so the row does not shuffle as it counts.
  /// What this is, which version of it is running, whether the system is letting it
  /// work, and where it keeps what it knows. Everything a person needs before
  /// reporting that something is wrong.
  private var aboutPage: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 4) {
          Text(localized("Tessera"))
            .font(.system(size: 15, weight: .semibold))
          Text(localized("A window switcher for macOS."))
            .foregroundStyle(.secondary)
          Text(localized("Version %@", AppInfo.version))
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
      }

      Section(localized("Permissions")) {
        setting(localized("Screen Recording"), AppInfo.screenRecordingStatus)
        setting(localized("Accessibility"), AppInfo.accessibilityStatus)
      }

      Section(localized("Files")) {
        VStack(alignment: .leading, spacing: 4) {
          Text(localized("Settings and the windows it has learned to leave out:"))
            .foregroundStyle(.secondary)
          Text(AppInfo.configurationDirectory)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
        }
      }
    }
  }

  /// Why there are two numbers that both start with "at most": one is the list the
  /// switcher keeps, the other is the map it draws from it.
  private var windowsNote: String {
    localized(
      """
      How many windows the switcher keeps in mind at all — every one of them holds \
      a preview in memory. What the overlay draws from that list is capped \
      separately, under Layout.
      """)
  }

  /// What the numbers above mean together: a ceiling and a floor, and a row length
  /// that only some of the arrangements are told.
  private var gridNote: String {
    let budget = localized(
      """
      At most %lld Spaces on the overlay, shared out between the displays, and none drawn \
      smaller than %lld points — what will not fit at that size is left off.
      """, model.overlayMaxCells, Int(model.overlayMinTile))

    guard model.overlayFillsScreen else {
      return budget + " "
        + String(
          localized: """
            The map is drawn at a fixed tile size, so the arrangement above is not \
            used and the row length is what shapes it.
            """)
    }

    guard model.overlayLayout == .rows else {
      return budget + " " + localized("This arrangement works its own row length out.")
    }

    return budget
  }

  private func setting(_ name: String, _ value: String) -> some View {
    HStack {
      Text(name)
      Spacer(minLength: 12)
      Text(value)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private func seconds(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))s" : String(format: "%.1fs", value)
  }
}
