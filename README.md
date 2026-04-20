# AeroSpaceSwitcher

Minimal native macOS workspace switcher for [AeroSpace](https://github.com/nikitabobko/AeroSpace).

The app runs as a background menu bar utility, keeps workspace previews in RAM, and shows a centered SwiftUI overlay for switching workspaces.

## Features

- Native macOS background utility app
- Menu bar item
- SwiftUI overlay switcher
- Workspace tiles for workspaces `1...7`
- Active workspace full snapshot
- Inactive workspace window thumbnails or fallback cards
- In-memory preview cache only
- CLI commands for debugging and automation

Screenshots and thumbnails are not written to disk. Preview images live only in process memory.

## Build

```sh
swift build
swift build -c release
```

The local convenience binary can point at the release build:

```sh
ln -sf "$PWD/.build/release/AeroSpaceSwitcher" ~/.local/bin/aerospaceswitcher
```

## Run The Background App

```sh
swift run AeroSpaceSwitcher gui
```

Or, after a release build:

```sh
aerospaceswitcher gui
```

The app stays alive in the background. Closing the overlay does not quit the app.

## CLI

```sh
aerospaceswitcher workspaces
aerospaceswitcher windows
aerospaceswitcher overview
aerospaceswitcher switch 3
aerospaceswitcher show
aerospaceswitcher toggle
```

`show` and `toggle` talk to the running background app through `DistributedNotificationCenter`.

Current notification contract:

- show name: `com.aerospace-switcher.show-switcher`
- toggle name: `com.aerospace-switcher.toggle-switcher`
- object: `com.aerospace-switcher`
- receiver suspension behavior: `deliverImmediately`

## Config

Example config:

```sh
cp config.example.toml ~/.config/aerospace-switcher/config.toml
```

If the config file is missing or partially invalid, the app falls back to defaults.

Useful settings:

```toml
refresh_interval_seconds = 3
full_snapshot_stale_seconds = 15
window_thumbnails_stale_seconds = 30

full_snapshot_target_width = 480
full_snapshot_target_height = 300
window_thumbnail_target_width = 240
window_thumbnail_target_height = 160
max_window_thumbnails_per_workspace = 4

close_after_workspace_switch = true
show_menu_bar_icon = true
refresh_focused_workspace_only = true
debug_mode = false
```

## Logs

```sh
log stream --info --debug --predicate 'subsystem == "com.aerospace-switcher"'
```

Useful source markers:

- `menu_bar_action`
- `external_show_command`
- `external_toggle_command`
- `internal_activation`
- `unexpected_external_trigger`

## Project Structure

```text
Sources/AeroSpaceSwitcher/
  AeroSpaceClient.swift              AeroSpace command backend
  AppConfig.swift                    Runtime configuration model
  AppConfigLoader.swift              TOML config loading
  AppCoordinator.swift               App lifecycle and trigger routing
  AppEntry.swift                     CLI/GUI entrypoint
  AppLogger.swift                    OSLog wrapper
  BackgroundAppNotifications.swift   Distributed notification contract
  CLI.swift                          CLI commands
  MenuBarController.swift            Menu bar integration
  Models.swift                       Shared models
  OverlayView.swift                  SwiftUI switcher UI
  OverlayWindowController.swift      Native overlay window
  PreviewCoordinator.swift           Preview refresh pipeline
  WindowThumbnailService.swift       ScreenCaptureKit window thumbnails
  WorkspacePreviewCache.swift        In-memory preview cache
  WorkspaceScreenshotService.swift   Focused workspace snapshot service
```

## TODO

- Add an internal global hotkey with `RegisterEventHotKey` inside the background app.
- Keep `DistributedNotificationCenter` for explicit CLI automation only.
- Make the primary hotkey path direct: `HotkeyController -> AppCoordinator.showOverlay(...)`.
- Avoid routing the main hotkey through `CLI -> DistributedNotificationCenter -> background app`.
