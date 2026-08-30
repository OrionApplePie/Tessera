import Foundation
import Testing

@testable import Tessera

/// The distributed notification names are a wire contract between the CLI and a
/// background app that may be an older build. Pin them so a rename has to be deliberate.
@Suite("BackgroundAppNotifications")
struct BackgroundAppNotificationsTests {
  @Test("The notification names and object are the documented ones")
  func namesMatchTheDocumentedContract() {
    #expect(BackgroundAppNotifications.notificationObject == "com.tessera")
    #expect(BackgroundAppNotifications.showSwitcher.rawValue == "com.tessera.show-switcher")
    #expect(BackgroundAppNotifications.toggleSwitcher.rawValue == "com.tessera.toggle-switcher")
    #expect(BackgroundAppNotifications.quitApp.rawValue == "com.tessera.quit-app")
    #expect(BackgroundAppNotifications.openSettings.rawValue == "com.tessera.open-settings")
  }

  @Test("The payload carries the source, the command and the sending process")
  func payloadIdentifiesTheSender() throws {
    let userInfo = BackgroundAppNotifications.userInfo(
      source: .externalShowCommand, command: "show")

    #expect(
      userInfo[BackgroundAppNotifications.sourceUserInfoKey] as? String == "external_show_command"
    )
    #expect(userInfo[BackgroundAppNotifications.commandUserInfoKey] as? String == "show")
    #expect(
      userInfo[BackgroundAppNotifications.senderPIDUserInfoKey] as? Int32
        == ProcessInfo.processInfo.processIdentifier
    )
    #expect(userInfo[BackgroundAppNotifications.timestampUserInfoKey] is TimeInterval)
  }

  @Test("Every post carries a fresh event id, so a receiver can drop duplicates")
  func eventIDIsUniquePerPost() throws {
    let first = BackgroundAppNotifications.userInfo(source: .menuBarAction, command: "toggle")
    let second = BackgroundAppNotifications.userInfo(source: .menuBarAction, command: "toggle")

    let firstID = try #require(first[BackgroundAppNotifications.eventIDUserInfoKey] as? String)
    let secondID = try #require(second[BackgroundAppNotifications.eventIDUserInfoKey] as? String)

    #expect(UUID(uuidString: firstID) != nil)
    #expect(firstID != secondID)
  }

  @Test("Command sources keep the raw values the logs are read against")
  func commandSourceRawValues() {
    #expect(AppCommandSource.externalShowCommand.rawValue == "external_show_command")
    #expect(AppCommandSource.externalToggleCommand.rawValue == "external_toggle_command")
    #expect(AppCommandSource.externalQuitCommand.rawValue == "external_quit_command")
    #expect(
      AppCommandSource.externalSettingsCommand.rawValue == "external_settings_command")
    #expect(AppCommandSource.externalRestartCommand.rawValue == "external_restart_command")
    #expect(AppCommandSource.globalHotkey.rawValue == "global_hotkey")
    #expect(AppCommandSource.menuBarAction.rawValue == "menu_bar_action")
    #expect(AppCommandSource.internalActivation.rawValue == "internal_activation")
    #expect(AppCommandSource.unexpectedExternalTrigger.rawValue == "unexpected_external_trigger")
  }
}
