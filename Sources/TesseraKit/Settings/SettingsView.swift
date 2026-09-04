import SwiftUI

/// A page of the settings window, and the list on its left.
enum SettingsSection: String, CaseIterable, Identifiable {
  case overlay
  case layout
  case previews
  case behaviour
  case timing
  case about

  var id: String {
    rawValue
  }

  var title: String {
    switch self {
    case .overlay:
      return "Overlay"
    case .layout:
      return "Layout"
    case .previews:
      return "Previews"
    case .behaviour:
      return "Behaviour"
    case .timing:
      return "Timing"
    case .about:
      return "About"
    }
  }

  var symbol: String {
    switch self {
    case .overlay:
      return "macwindow"
    case .layout:
      return "square.grid.2x2"
    case .previews:
      return "photo"
    case .behaviour:
      return "gearshape"
    case .timing:
      return "timer"
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
    section: SettingsSection = .overlay,
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
    case .overlay:
      overlayPage
    case .layout:
      layoutPage
    case .previews:
      previewsPage
    case .behaviour:
      behaviourPage
    case .timing:
      timingPage
    case .about:
      aboutPage
    }
  }

  private var overlayPage: some View {
    Form {
      Section("Shortcut") {
        TextField("Show the overlay", text: $model.hotkey, prompt: Text("ctrl+alt+space"))

        TextField("Close a window", text: $model.closeHotkey, prompt: Text("cmd+w"))

        Picker("Closing", selection: $model.closeAction) {
          Text("Closes the window").tag(CloseAction.closeWindow)
          Text("Quits the application").tag(CloseAction.quitApplication)
        }
      }

      Section("Appearance") {
        ColorPicker("Background", selection: $model.background, supportsOpacity: true)
      }
    }
  }

  /// The shape of the map: how many Spaces stand where, how large they are drawn,
  /// and what a keypress moves through.
  private var layoutPage: some View {
    Form {
      Section("The map") {
        Picker("Arrange", selection: $model.overlayLayout) {
          Text("As large as the screen allows").tag(OverlayLayout.fitted)
          Text("A fixed number across").tag(OverlayLayout.rows)
          Text("A square, by how many there are").tag(OverlayLayout.count)
          Text("One after another, wrapping").tag(OverlayLayout.flow)
        }

        Stepper(value: $model.overlayColumns, in: 1...12) {
          setting("Spaces across", "\(model.overlayColumns)")
        }

        Stepper(value: $model.overlayMaxCells, in: 1...60) {
          setting("At most", "\(model.overlayMaxCells) Spaces")
        }

        Stepper(value: $model.overlayMinTile, in: 90...400, step: 10) {
          setting("Smallest tile", "\(Int(model.overlayMinTile)) pt")
        }

        Text(gridNote)
          .font(.caption)
          .foregroundStyle(.secondary)

        Picker("Short rows sit", selection: $model.overlayRowAlignment) {
          Text("In the middle").tag(OverlayRowAlignment.center)
          Text("To the left").tag(OverlayRowAlignment.leading)
          Text("To the right").tag(OverlayRowAlignment.trailing)
        }

        Toggle("Grow the map into the screen", isOn: $model.overlayFillsScreen)
      }

      Section("Groups") {
        Picker("A Space of several windows", selection: $model.overlayDeck) {
          Text("One card, turned through").tag(OverlayDeckStyle.stack)
          Text("Cards side by side").tag(OverlayDeckStyle.fan)
        }

        Toggle("Group by display", isOn: $model.groupsDisplays)
        Toggle("Group by Space", isOn: $model.groupsSpaces)
      }

      Section("Order") {
        Picker("Arrows move by", selection: $model.overlayArrows) {
          Text("Space, Tab for its windows").tag(OverlayArrowStep.spaces)
          Text("Window").tag(OverlayArrowStep.windows)
        }

        Picker("Typing a letter", selection: $model.overlaySearch) {
          Text("Walks the windows of that name").tag(OverlaySearch.letter)
          Text("Searches, letter by letter").tag(OverlaySearch.fuzzy)
        }

        Picker("Windows in a group", selection: $model.windowOrder) {
          Text("Application and title").tag(WindowOrder.title)
          Text("Application only").tag(WindowOrder.application)
          Text("Never reorder").tag(WindowOrder.stable)
        }
      }
    }
  }

  private var previewsPage: some View {
    Form {
      Section("Contents") {
        Picker("Show", selection: $model.thumbnailMode) {
          Text("The whole window").tag(WindowThumbnailMode.fit)
          Text("Its corner, at actual size").tag(WindowThumbnailMode.corner)
          Text("Its corner, twice as much").tag(WindowThumbnailMode.cornerDouble)
          Text("Roughly a quarter of it").tag(WindowThumbnailMode.quarter)
          Text("Three quarters of it").tag(WindowThumbnailMode.threeQuarters)
        }

        Picker("Capture at", selection: $model.thumbnailQuality) {
          Text("What the tile shows").tag(ThumbnailQuality.tile)
          Text("HD, sharper and heavier").tag(ThumbnailQuality.hd)
          Text("The most, and the most memory").tag(ThumbnailQuality.max)
        }
      }

      Section("Refresh") {
        Stepper(value: $model.refreshIntervalSeconds, in: 0.5...60, step: 0.5) {
          setting("Every", seconds(model.refreshIntervalSeconds))
        }
        Stepper(value: $model.windowThumbnailsStaleSeconds, in: 1...600, step: 5) {
          setting("Stale after", seconds(model.windowThumbnailsStaleSeconds))
        }
        Toggle("Fade a stale preview", isOn: $model.dimsStaleThumbnails)
      }

    }
  }

  /// Everything the switcher waits for. Each of these is a compromise measured on
  /// a real desktop rather than a value with a right answer, so each is here.
  private var timingPage: some View {
    Form {
      Section("Reaching a window") {
        Stepper(value: $model.activationSettleSeconds, in: 0.5...10, step: 0.5) {
          setting("Let the system settle for", seconds(model.activationSettleSeconds))
        }
      }

      Section("Waiting for an answer") {
        Stepper(value: $model.unresponsiveAfterSeconds, in: 0.5...30, step: 0.5) {
          setting("Wedged after", seconds(model.unresponsiveAfterSeconds))
        }
      }
    }
  }

  private var behaviourPage: some View {
    Form {
      Section("Windows") {
        TextField(
          "Ignore applications",
          text: $model.ignoredApplications,
          prompt: Text("AmneziaVPN, Some Tray App")
        )
        Stepper(value: $model.maxWindows, in: 1...96) {
          setting("Never list more than", "\(model.maxWindows) windows")
        }

        Text(windowsNote)
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle("Close the overlay after switching", isOn: $model.closeAfterActivation)
        Toggle("Leave out menu bar applications", isOn: $model.ignoresMenuBarApplications)
      }

      Section("App") {
        Toggle("Ask the window server which Space a window is on", isOn: $model.usesPrivateSpaceAPI)
        Toggle("Show the menu bar icon", isOn: $model.showMenuBarIcon)
        Toggle("Verbose logging", isOn: $model.debugMode)
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

      Button("Cancel", action: onCancel)
        .keyboardShortcut(.cancelAction)
      Button("Save and Restart", action: onSave)
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
          Text("Tessera")
            .font(.system(size: 15, weight: .semibold))
          Text("A window switcher for macOS.")
            .foregroundStyle(.secondary)
          Text("Version \(AppInfo.version)")
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 2)
      }

      Section("Permissions") {
        setting("Screen Recording", AppInfo.screenRecordingStatus)
        setting("Accessibility", AppInfo.accessibilityStatus)
      }

      Section("Files") {
        VStack(alignment: .leading, spacing: 4) {
          Text("Settings and the windows it has learned to leave out:")
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
    String(
      localized: """
        How many windows the switcher keeps in mind at all — every one of them holds \
        a preview in memory. What the overlay draws from that list is capped \
        separately, under Layout.
        """)
  }

  /// What the numbers above mean together: a ceiling and a floor, and a row length
  /// that only the fixed layout is told.
  private var gridNote: String {
    let budget = String(
      localized: """
        At most \(model.overlayMaxCells) Spaces on the map, shared out between the displays, \
        and none drawn smaller than \(Int(model.overlayMinTile)) points — what will not fit \
        at that size is left off.
        """)

    guard model.overlayLayout == .rows else {
      return budget + " " + String(localized: "This layout works its own row length out.")
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
