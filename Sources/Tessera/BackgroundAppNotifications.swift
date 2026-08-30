import Foundation

enum BackgroundAppNotifications {
  static let notificationObject = "com.tessera"
  static let showSwitcher = Notification.Name("com.tessera.show-switcher")
  static let toggleSwitcher = Notification.Name("com.tessera.toggle-switcher")
  static let quitApp = Notification.Name("com.tessera.quit-app")

  static let sourceUserInfoKey = "source"
  static let eventIDUserInfoKey = "event_id"
  static let senderPIDUserInfoKey = "sender_pid"
  static let commandUserInfoKey = "command"
  static let timestampUserInfoKey = "timestamp"

  static func userInfo(source: AppCommandSource, command: String) -> [String: Any] {
    [
      sourceUserInfoKey: source.rawValue,
      eventIDUserInfoKey: UUID().uuidString,
      senderPIDUserInfoKey: ProcessInfo.processInfo.processIdentifier,
      commandUserInfoKey: command,
      timestampUserInfoKey: Date().timeIntervalSince1970,
    ]
  }
}

enum AppCommandSource: String {
  case externalShowCommand = "external_show_command"
  case externalToggleCommand = "external_toggle_command"
  case externalQuitCommand = "external_quit_command"
  case externalRestartCommand = "external_restart_command"
  case globalHotkey = "global_hotkey"
  case menuBarAction = "menu_bar_action"
  case internalActivation = "internal_activation"
  case unexpectedExternalTrigger = "unexpected_external_trigger"
}
