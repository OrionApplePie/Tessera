import Testing

@testable import TesseraKit

@Suite("MediaControl")
struct MediaControlTests {
  /// The point of addressing an application rather than pressing a media key: a
  /// player that is sitting there silent can still be told to start.
  @Test("A scriptable player is addressed by name")
  func addressesAScriptablePlayer() {
    #expect(
      MediaControl.script(forBundleIdentifier: "com.spotify.client", .playPause)
        == "tell application \"Spotify\" to playpause")
    #expect(
      MediaControl.script(forBundleIdentifier: "com.apple.Music", .next)
        == "tell application \"Music\" to next track")
    #expect(
      MediaControl.script(forBundleIdentifier: "com.apple.Music", .previous)
        == "tell application \"Music\" to previous track")
  }

  /// VLC understands the same three commands under different names.
  @Test("VLC gets the words VLC knows")
  func speaksVLCsDialect() {
    #expect(
      MediaControl.script(forBundleIdentifier: "org.videolan.vlc", .playPause)
        == "tell application \"VLC\" to play")
    #expect(
      MediaControl.script(forBundleIdentifier: "org.videolan.vlc", .next)
        == "tell application \"VLC\" to next")
  }

  /// Everything else gets nothing, which is what lets the caller say so instead of
  /// sending a keystroke hopefully at whatever has the keyboard.
  @Test("An application that takes no commands is not guessed at")
  func refusesWhatItCannotAddress() {
    #expect(MediaControl.script(forBundleIdentifier: "com.google.Chrome", .playPause) == nil)
    #expect(MediaControl.script(forBundleIdentifier: nil, .playPause) == nil)
    #expect(MediaControl.script(forBundleIdentifier: "", .next) == nil)
  }
}
