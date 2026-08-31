import SwiftUI

/// A page of the settings window, and the list on its left.
enum SettingsSection: String, CaseIterable, Identifiable {
  case overlay
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
        TextField("Hotkey", text: $model.hotkey, prompt: Text("ctrl+alt+space"))
      }

      Section("Layout") {
        Stepper(value: $model.overlayColumns, in: 1...12) {
          setting("Columns", "\(model.overlayColumns)")
        }

        Picker("Tile order", selection: $model.windowOrder) {
          Text("Application and title").tag(WindowOrder.title)
          Text("Application only").tag(WindowOrder.application)
          Text("Never reorder").tag(WindowOrder.stable)
        }

        Toggle("Group by display", isOn: $model.groupsDisplays)
        Toggle("Group by Space", isOn: $model.groupsSpaces)
      }

      Section("Appearance") {
        ColorPicker("Background", selection: $model.background, supportsOpacity: true)
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

      Section("Size") {
        // A corner is captured at the size the tile draws it, so a target size has
        // nothing to act on there.
        Stepper(value: $model.thumbnailWidth, in: 40...960, step: 20) {
          setting("Width", "\(Int(model.thumbnailWidth))")
        }
        .disabled(model.thumbnailMode != .fit)

        Stepper(value: $model.thumbnailHeight, in: 40...960, step: 20) {
          setting("Height", "\(Int(model.thumbnailHeight))")
        }
        .disabled(model.thumbnailMode != .fit)

        Stepper(value: $model.maxWindows, in: 1...96) {
          setting("At most", "\(model.maxWindows) windows")
        }
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
        Toggle("Close the overlay after switching", isOn: $model.closeAfterActivation)
      }

      Section("App") {
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
