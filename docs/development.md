# Building and working on it

How to build and test it, how the sources are laid out, and what is left to do.

- [Build](#build)
- [Project Structure](#project-structure)
- [Tests](#tests)
- [Design notes](#design-notes)
- [TODO](#todo)

## Build

```sh
make build
make build CONFIG=release
```

The local convenience binary can point at the release build:

```sh
ln -sf "$PWD/.build/release/Tessera" ~/.local/bin/tessera
```

## Project Structure

```text
docs/mechanisms.md                     Why the non-obvious parts work as they do
docs/packaging.md                      How it is installed, and what a release needs
Formula/tessera.rb                     The Homebrew formula, copied into the tap
LICENSE                                GNU General Public License v3.0

Sources/Tessera/main.swift             The executable: one line calling the library

Sources/TesseraKit/
  App/
    AppCoordinator.swift               App lifecycle and trigger routing
    AppEntry.swift                     CLI/GUI entrypoint
    AppInfo.swift                      Version and paths the About page shows
    BackgroundAppLauncher.swift        Starting and replacing the background app
    BackgroundAppNotifications.swift   Distributed notification contract
    MenuBarController.swift            Menu bar integration
    SingleInstanceLock.swift           Background app single-instance guard

  CommandLine/
    CLI.swift                          CLI commands

  Config/
    AppConfig.swift                    Runtime configuration model
    AppConfigLoader.swift              TOML config loading
    AppConfigWriter.swift              Writing the config back out
    CloseAction.swift                  What the close shortcut does
    OverlayArrowStep.swift             What an arrow counts in
    OverlayDeckStyle.swift             How a Space's windows are stacked
    OverlayGrouping.swift              Whether the overlay groups by Space
    OverlayLayout.swift                How the Spaces are arranged
    OverlayRowAlignment.swift          Where a short row sits under a long one
    OverlaySearch.swift                What typing at the overlay does
    ThumbnailQuality.swift             How many pixels a capture is worth
    WindowOrder.swift                  Tile order and the places it hands out
    WindowThumbnailMode.swift          What part of a window a tile shows

  Windows/
    ActivationVerifier.swift           Judging what an activation actually did
    FrontmostWindow.swift              Which window you are coming from
    LearnedWindowStore.swift           Windows that ignored an activation
    MinimizedWindowService.swift       Which windows are in the Dock
    Models.swift                       Shared models
    WindowActivator.swift              Window focus via NSRunningApplication + Accessibility
    WindowCoordinator.swift            Window list and thumbnail refresh pipeline
    WindowCoordinatorActions.swift     Moving, placing and fullscreening a window
    WindowListService.swift            ScreenCaptureKit window enumeration
    WindowMenuActivator.swift          Raising a window through its Window menu
    WindowPlacement.swift              Halves of a screen, and the whole of it
    WindowTitleMatch.swift             Matching a title against what an app reports

  Spaces/
    DesktopSwitcher.swift              Showing a desktop by its system shortcut
    DesktopWallpaper.swift             The picture an empty Space is drawn with
    DisplayInfo.swift                  Which display a window sits on
    SpaceQuery.swift                   The window server's own answers about Spaces
    SpaceTracker.swift                 Learns which windows share a Space

  Thumbnails/
    WindowPreviewCache.swift           In-memory thumbnail cache
    WindowThumbnailService.swift       ScreenCaptureKit window thumbnails

  Overlay/
    HoldToSwitchController.swift       Holding ⌃⌥ and switching on release
    OverlayFitting.swift               Choosing the tile size and the panel's size
    OverlayGrid.swift                  Arrow-key navigation over the tile grid
    OverlayHold.swift                  The overlay's side of hold-to-switch
    OverlayPanel.swift                 The panel and every key it answers to
    OverlayTyping.swift                Finding a window by typing
    OverlayView.swift                  SwiftUI switcher UI
    OverlayWindowController.swift      Native overlay window

  Search/
    FuzzyMatch.swift                   Scoring a typed query against a name
    KeyboardLayouts.swift              What a key means in every layout enabled
    WindowSearch.swift                 Ranking the overlay against what was typed

  Hotkeys/
    HotkeyBinding.swift                Hotkey spec parsing and Carbon key codes
    HotkeyController.swift             Global hotkey registration
    StepHotkeyController.swift         Keys held while stepping through windows
    SystemHotkeys.swift                Reading macOS's own shortcut table

  Settings/
    SettingsModel.swift                The window's editable copy of the config
    SettingsView.swift                 The settings window
    SettingsWindowController.swift     Opening and sizing that window

  Support/
    AppLogger.swift                    OSLog wrapper
    OverlayColor.swift                 Hex colour parsing for the overlay surface

Tests/TesseraKitTests/                 The same folders, one suite per subject
```

## Tests

```sh
make test
FILTER='AppConfigLoader' make test-one
```

Tests use swift-testing and touch neither the network nor the clock. Full Xcode
is not required: the Makefile points `swift test` and `swiftlint` at the Command
Line Tools toolchain when that is all that is installed.

`WindowCoordinator` and the ScreenCaptureKit services are not covered — they hold
concrete collaborators, so testing them means introducing protocols first.

## Design notes

`docs/mechanisms.md` explains why the non-obvious parts work the way they do —
window enumeration, display and Space resolution, the capture that never returns,
minimized windows, leftover tray windows — including what was measured and which
approaches were tried and rejected.

## TODO

- Tell a window an application no longer owns from one on another Space. Nothing
  public distinguishes them — see `docs/mechanisms.md`; the Window menu may, since
  it lists what the application still considers a window.

- Let the menu bar item show the current hotkey and report a failed registration,
  which today only reaches the log.
- Cover `WindowCoordinator` and the ScreenCaptureKit services; they take
  concrete collaborators today, so testing them needs protocols first.
