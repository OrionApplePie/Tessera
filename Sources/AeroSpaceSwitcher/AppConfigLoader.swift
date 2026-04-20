import Foundation

struct AppConfigLoader {
    let configURL: URL

    init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/aerospace-switcher/config.toml")
    ) {
        self.configURL = configURL
    }

    func load() -> AppConfig {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            return .default
        }

        do {
            let text = try String(contentsOf: configURL, encoding: .utf8)
            return try parse(text)
        } catch {
            fputs(
                "AeroSpaceSwitcher: failed to load config at \(configURL.path), using defaults: \(error)\n",
                stderr
            )
            return .default
        }
    }

    private func parse(_ text: String) throws -> AppConfig {
        var config = AppConfig.default
        let values = try parseKeyValues(text)

        config.refreshIntervalSeconds = try positiveDouble(
            values["refresh_interval_seconds"],
            default: config.refreshIntervalSeconds,
            key: "refresh_interval_seconds"
        )
        config.fullSnapshotStaleSeconds = try positiveDouble(
            values["full_snapshot_stale_seconds"],
            default: config.fullSnapshotStaleSeconds,
            key: "full_snapshot_stale_seconds"
        )
        config.windowThumbnailsStaleSeconds = try positiveDouble(
            values["window_thumbnails_stale_seconds"],
            default: config.windowThumbnailsStaleSeconds,
            key: "window_thumbnails_stale_seconds"
        )

        let fullWidth = try positiveDouble(
            values["full_snapshot_target_width"],
            default: config.fullSnapshotTargetSize.width,
            key: "full_snapshot_target_width"
        )
        let fullHeight = try positiveDouble(
            values["full_snapshot_target_height"],
            default: config.fullSnapshotTargetSize.height,
            key: "full_snapshot_target_height"
        )
        config.fullSnapshotTargetSize = CGSize(width: fullWidth, height: fullHeight)

        let thumbnailWidth = try positiveDouble(
            values["window_thumbnail_target_width"],
            default: config.windowThumbnailTargetSize.width,
            key: "window_thumbnail_target_width"
        )
        let thumbnailHeight = try positiveDouble(
            values["window_thumbnail_target_height"],
            default: config.windowThumbnailTargetSize.height,
            key: "window_thumbnail_target_height"
        )
        config.windowThumbnailTargetSize = CGSize(width: thumbnailWidth, height: thumbnailHeight)

        config.maxWindowThumbnailsPerWorkspace = try positiveInt(
            values["max_window_thumbnails_per_workspace"],
            default: config.maxWindowThumbnailsPerWorkspace,
            key: "max_window_thumbnails_per_workspace"
        )
        config.closeAfterWorkspaceSwitch = try bool(
            values["close_after_workspace_switch"],
            default: config.closeAfterWorkspaceSwitch,
            key: "close_after_workspace_switch"
        )
        config.showMenuBarIcon = try bool(
            values["show_menu_bar_icon"],
            default: config.showMenuBarIcon,
            key: "show_menu_bar_icon"
        )
        config.refreshFocusedWorkspaceOnly = try bool(
            values["refresh_focused_workspace_only"],
            default: config.refreshFocusedWorkspaceOnly,
            key: "refresh_focused_workspace_only"
        )

        return config
    }

    private func parseKeyValues(_ text: String) throws -> [String: String] {
        var values: [String: String] = [:]

        for (lineIndex, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !line.isEmpty else {
                continue
            }

            if line.hasPrefix("[") {
                throw AppConfigError.unsupportedSyntax(line: lineIndex + 1)
            }

            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw AppConfigError.invalidLine(line: lineIndex + 1)
            }

            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)

            guard !key.isEmpty, !value.isEmpty else {
                throw AppConfigError.invalidLine(line: lineIndex + 1)
            }

            values[key] = value
        }

        return values
    }

    private func stripComment(_ line: String) -> String {
        guard let commentStart = line.firstIndex(of: "#") else {
            return line
        }

        return String(line[..<commentStart])
    }

    private func positiveDouble(_ rawValue: String?, default defaultValue: Double, key: String) throws -> Double {
        guard let rawValue else {
            return defaultValue
        }

        guard let value = Double(rawValue), value > 0 else {
            throw AppConfigError.invalidValue(key: key)
        }

        return value
    }

    private func positiveInt(_ rawValue: String?, default defaultValue: Int, key: String) throws -> Int {
        guard let rawValue else {
            return defaultValue
        }

        guard let value = Int(rawValue), value > 0 else {
            throw AppConfigError.invalidValue(key: key)
        }

        return value
    }

    private func bool(_ rawValue: String?, default defaultValue: Bool, key: String) throws -> Bool {
        guard let rawValue else {
            return defaultValue
        }

        switch rawValue.lowercased() {
        case "true":
            return true
        case "false":
            return false
        default:
            throw AppConfigError.invalidValue(key: key)
        }
    }
}

enum AppConfigError: Error, CustomStringConvertible {
    case invalidLine(line: Int)
    case unsupportedSyntax(line: Int)
    case invalidValue(key: String)

    var description: String {
        switch self {
        case .invalidLine(let line):
            return "invalid TOML line \(line)"
        case .unsupportedSyntax(let line):
            return "unsupported TOML syntax on line \(line)"
        case .invalidValue(let key):
            return "invalid value for \(key)"
        }
    }
}

