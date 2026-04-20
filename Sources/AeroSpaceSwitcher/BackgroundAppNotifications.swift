import Foundation

enum BackgroundAppNotifications {
    static let notificationObject = "com.aerospace-switcher"
    static let showSwitcher = Notification.Name("com.aerospace-switcher.show-switcher")
    static let toggleSwitcher = Notification.Name("com.aerospace-switcher.toggle-switcher")

    static let sourceUserInfoKey = "source"
    static let eventIDUserInfoKey = "event_id"
    static let senderPIDUserInfoKey = "sender_pid"
    static let commandUserInfoKey = "command"
    static let timestampUserInfoKey = "timestamp"

    static func userInfo(source: OverlayOpenSource, command: String) -> [String: Any] {
        [
            sourceUserInfoKey: source.rawValue,
            eventIDUserInfoKey: UUID().uuidString,
            senderPIDUserInfoKey: ProcessInfo.processInfo.processIdentifier,
            commandUserInfoKey: command,
            timestampUserInfoKey: Date().timeIntervalSince1970
        ]
    }
}

enum OverlayOpenSource: String {
    case externalShowCommand = "external_show_command"
    case externalToggleCommand = "external_toggle_command"
    case menuBarAction = "menu_bar_action"
    case internalActivation = "internal_activation"
    case unexpectedExternalTrigger = "unexpected_external_trigger"
}
