import AppKit
import CoreGraphics
import Foundation
import SwiftUI

/// The settings window's editable copy of the configuration.
///
/// Text fields hold text, not parsed values: a hotkey being typed passes through
/// states that are not yet a hotkey, and refusing to let someone type is worse
/// than telling them at the end what did not parse.
@MainActor
final class SettingsModel: ObservableObject {
  @Published var hotkey: String
  @Published var ignoredApplications: String
  @Published var background: Color

  @Published var overlayColumns: Int
  @Published var windowOrder: WindowOrder
  @Published var groupsDisplays: Bool
  @Published var groupsSpaces: Bool

  @Published var refreshIntervalSeconds: Double
  @Published var windowThumbnailsStaleSeconds: Double
  @Published var dimsStaleThumbnails: Bool
  @Published var thumbnailWidth: Double
  @Published var thumbnailHeight: Double
  @Published var maxWindows: Int

  @Published var closeAfterActivation: Bool
  @Published var showMenuBarIcon: Bool
  @Published var debugMode: Bool

  @Published private(set) var problem: String?

  init(config: AppConfig) {
    hotkey = config.hotkey?.displayName ?? ""
    ignoredApplications = config.ignoredApplications.sorted().joined(separator: ", ")
    background = Color(config.overlayBackground)
    overlayColumns = config.overlayColumns
    windowOrder = config.windowOrder
    groupsDisplays = config.overlayGrouping.contains(.displays)
    groupsSpaces = config.overlayGrouping.contains(.spaces)
    refreshIntervalSeconds = config.refreshIntervalSeconds
    windowThumbnailsStaleSeconds = config.windowThumbnailsStaleSeconds
    dimsStaleThumbnails = config.dimsStaleThumbnails
    thumbnailWidth = config.windowThumbnailTargetSize.width
    thumbnailHeight = config.windowThumbnailTargetSize.height
    maxWindows = config.maxWindows
    closeAfterActivation = config.closeAfterActivation
    showMenuBarIcon = config.showMenuBarIcon
    debugMode = config.debugMode
  }

  /// The configuration as edited, or `nil` with `problem` set to what is wrong.
  func makeConfig() -> AppConfig? {
    problem = nil

    var config = AppConfig.default

    let spec = hotkey.trimmingCharacters(in: .whitespaces)
    if spec.isEmpty {
      config.hotkey = nil
    } else {
      do {
        config.hotkey = try HotkeyBinding(parsing: spec)
      } catch {
        problem = "\(error)"
        return nil
      }
    }

    config.overlayBackground = OverlayColor(background)
    config.ignoredApplications = Set(
      ignoredApplications
        .split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        .filter { !$0.isEmpty }
    )

    var grouping: OverlayGrouping = []
    if groupsDisplays {
      grouping.insert(.displays)
    }
    if groupsSpaces {
      grouping.insert(.spaces)
    }
    config.overlayGrouping = grouping

    config.overlayColumns = max(1, overlayColumns)
    config.windowOrder = windowOrder
    config.refreshIntervalSeconds = max(0.5, refreshIntervalSeconds)
    config.windowThumbnailsStaleSeconds = max(1, windowThumbnailsStaleSeconds)
    config.dimsStaleThumbnails = dimsStaleThumbnails
    config.windowThumbnailTargetSize = CGSize(
      width: max(40, thumbnailWidth),
      height: max(40, thumbnailHeight)
    )
    config.maxWindows = max(1, maxWindows)
    config.closeAfterActivation = closeAfterActivation
    config.showMenuBarIcon = showMenuBarIcon
    config.debugMode = debugMode

    return config
  }
}

extension OverlayColor {
  /// SwiftUI hands back a `Color` in whatever space the picker used; the config
  /// stores sRGB components, so it is converted rather than assumed.
  init(_ color: Color) {
    let converted = NSColor(color).usingColorSpace(.sRGB)

    self.init(
      red: Double(converted?.redComponent ?? 0),
      green: Double(converted?.greenComponent ?? 0),
      blue: Double(converted?.blueComponent ?? 0),
      alpha: Double(converted?.alphaComponent ?? 1)
    )
  }
}
