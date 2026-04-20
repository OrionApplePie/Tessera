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
swift run AeroSpaceSwitcher run
```

Or, after a release build:

```sh
aerospaceswitcher run
```

The app stays alive in the background. Closing the overlay does not quit the app.

`run` is idempotent: if a background instance is already running, the new `run` process exits without creating a second menu bar item or a second preview service.

## CLI

```sh
aerospaceswitcher run
aerospaceswitcher show
aerospaceswitcher toggle
aerospaceswitcher quit
aerospaceswitcher restart
aerospaceswitcher workspaces
aerospaceswitcher windows
aerospaceswitcher overview
aerospaceswitcher switch 3
```

Primary lifecycle commands:

- `run` starts the background app if it is not already running.
- `show` shows the workspace switcher overlay in the running background app.
- `toggle` toggles overlay visibility.
- `quit` asks the running background app to stop cleanly.
- `restart` asks the running background app to stop, then launches a fresh `run`.

Debug / utility commands:

- `workspaces`
- `windows`
- `overview`
- `switch <id>`

`show`, `toggle`, `quit`, and `restart` talk to the running background app through `DistributedNotificationCenter`.

Current notification contract:

- show name: `com.aerospace-switcher.show-switcher`
- toggle name: `com.aerospace-switcher.toggle-switcher`
- quit name: `com.aerospace-switcher.quit-app`
- object: `com.aerospace-switcher`
- receiver suspension behavior: `deliverImmediately`

## Lifecycle

`AeroSpaceSwitcher` uses an app-level `flock` guard at:

```text
~/.config/aerospace-switcher/aerospace-switcher.lock
```

Only the long-running `run` process holds this lock. Sender commands such as `show`, `toggle`, `quit`, and `restart` do not acquire it as long-running app instances.

This keeps repeated launches safe:

- first `aerospaceswitcher run` starts the background app
- second `aerospaceswitcher run` exits without creating a duplicate
- `aerospaceswitcher restart` is the explicit command for controlled replacement
- `aerospaceswitcher quit` stops refresh tasks, clears the in-memory preview cache, removes observers, and terminates the app

## AeroSpace Integration

Recommended `after-startup-command`:

```toml
after-startup-command = ['exec-and-forget /Users/alex/.local/bin/aerospaceswitcher run']
```

Recommended hotkey command until the app has an internal global hotkey:

```toml
ctrl-9 = 'exec-and-forget /Users/alex/.local/bin/aerospaceswitcher show'
```

Do not use the old `gui` command. It has been removed.

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
- `external_quit_command`
- `external_restart_command`
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
  SingleInstanceLock.swift           Background app single-instance guard
  WindowThumbnailService.swift       ScreenCaptureKit window thumbnails
  WorkspacePreviewCache.swift        In-memory preview cache
  WorkspaceScreenshotService.swift   Focused workspace snapshot service
```

## TODO

- Add an internal global hotkey with `RegisterEventHotKey` inside the background app.
- Keep `DistributedNotificationCenter` for explicit CLI automation only.
- Make the primary hotkey path direct: `HotkeyController -> AppCoordinator.showOverlay(...)`.
- Avoid routing the main hotkey through `CLI -> DistributedNotificationCenter -> background app`.
