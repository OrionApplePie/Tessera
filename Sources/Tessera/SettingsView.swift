import SwiftUI

/// A page of the settings window, and the list on its left.
enum SettingsSection: String, CaseIterable, Identifiable {
  case overlay
  case previews
  case behaviour
  case timing

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

  @State private var section: SettingsSection = .overlay

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 0) {
        List(SettingsSection.allCases, selection: $section) { section in
          Label(section.title, systemImage: section.symbol)
            .tag(section)
        }
        .listStyle(.sidebar)
        .frame(width: 168)

        Divider()

        page
          .formStyle(.grouped)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }

      Divider()
      footer
    }
    // Landscape: a list of sections down the side and one page beside it, rather
    // than one long column that has to be scrolled past what you are not editing.
    .frame(minWidth: 640, idealWidth: 720, minHeight: 400, idealHeight: 460)
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
    }
  }

  private var overlayPage: some View {
    Form {
      Section("Shortcut") {
        TextField("Hotkey", text: $model.hotkey, prompt: Text("ctrl+alt+space"))
      }

      Section("Layout") {
        Stepper("Columns: \(model.overlayColumns)", value: $model.overlayColumns, in: 1...12)

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
        Stepper(
          "Every \(seconds(model.refreshIntervalSeconds))",
          value: $model.refreshIntervalSeconds,
          in: 0.5...60,
          step: 0.5
        )
        Stepper(
          "Stale after \(seconds(model.windowThumbnailsStaleSeconds))",
          value: $model.windowThumbnailsStaleSeconds,
          in: 1...600,
          step: 5
        )
        Toggle("Fade a stale preview", isOn: $model.dimsStaleThumbnails)
      }

      Section("Size") {
        // A corner is captured at the size the tile draws it, so a target size has
        // nothing to act on there.
        Stepper(
          "Width: \(Int(model.thumbnailWidth))",
          value: $model.thumbnailWidth,
          in: 40...960,
          step: 20
        )
        .disabled(model.thumbnailMode != .fit)

        Stepper(
          "Height: \(Int(model.thumbnailHeight))",
          value: $model.thumbnailHeight,
          in: 40...960,
          step: 20
        )
        .disabled(model.thumbnailMode != .fit)

        Stepper("At most \(model.maxWindows) windows", value: $model.maxWindows, in: 1...96)
      }
    }
  }

  /// Everything the switcher waits for. Each of these is a compromise measured on
  /// a real desktop rather than a value with a right answer, so each is here.
  private var timingPage: some View {
    Form {
      Section("Reaching a window") {
        Stepper(
          "Give the system \(seconds(model.activationSettleSeconds)) to settle",
          value: $model.activationSettleSeconds,
          in: 0.5...10,
          step: 0.5
        )
      }

      Section("Waiting for an answer") {
        Stepper(
          "Wedged after \(seconds(model.unresponsiveAfterSeconds))",
          value: $model.unresponsiveAfterSeconds,
          in: 0.5...30,
          step: 0.5
        )
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

  private func seconds(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))s" : String(format: "%.1fs", value)
  }
}
