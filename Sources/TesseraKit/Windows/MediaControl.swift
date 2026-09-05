import AppKit
import Foundation

/// Telling one particular application to play, when the media keys cannot.
///
/// A media key is a system-wide event: macOS gives it to whatever it considers the
/// application that is playing, which is no use for starting something that is
/// silent. Spotify and Music answer to Apple events instead, and an Apple event is
/// addressed — "play" reaches the application it names and nothing else.
///
/// Only the players that are scriptable are here, and only the four commands that
/// every one of them understands. An application that is not on this list and is
/// not making a sound cannot be told anything, which is the honest answer rather
/// than a keystroke sent hopefully at whatever has the keyboard.
enum MediaControl {
  /// The applications this can address, by bundle identifier, with the name Apple
  /// events know them by.
  private static let players: [String: String] = [
    "com.spotify.client": "Spotify",
    "com.apple.Music": "Music",
    "com.apple.iTunes": "iTunes",
    "com.apple.TV": "TV",
    "org.videolan.vlc": "VLC",
  ]

  /// The script that sends one command to one application, or nothing when that
  /// application does not take commands.
  nonisolated static func script(
    forBundleIdentifier identifier: String?,
    _ command: MediaKeys.Command
  ) -> String? {
    guard let identifier, let application = players[identifier] else {
      return nil
    }

    // VLC spells the same three commands differently, and calls them of its own
    // window rather than of the application.
    let verb: String

    switch (command, application) {
    case (.playPause, "VLC"):
      verb = "play"
    case (.playPause, _):
      verb = "playpause"
    case (.next, "VLC"):
      verb = "next"
    case (.next, _):
      verb = "next track"
    case (.previous, "VLC"):
      verb = "previous"
    case (.previous, _):
      verb = "previous track"
    }

    return "tell application \"\(application)\" to \(verb)"
  }

  /// Runs it, and says whether it went through.
  ///
  /// The first one of these puts up the permission dialog for controlling that
  /// application; refused, it fails here and the caller says so rather than looking
  /// as though the key did nothing.
  @MainActor
  static func run(_ script: String) -> (ran: Bool, problem: String?) {
    var error: NSDictionary?

    guard let compiled = NSAppleScript(source: script) else {
      return (false, "the script would not compile")
    }

    compiled.executeAndReturnError(&error)

    guard let error else {
      return (true, nil)
    }

    return (false, error[NSAppleScript.errorMessage] as? String ?? "\(error)")
  }
}
