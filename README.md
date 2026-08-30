# Tessera

Native macOS window switcher.

Tessera runs as a background menu bar utility, keeps window previews in RAM, and
shows a centered SwiftUI overlay for switching between open windows.

It depends on no external tool. Windows are discovered through ScreenCaptureKit
and focused through `NSRunningApplication` plus the Accessibility API — all
public macOS frameworks.

## Features

- Native macOS background utility app
- Configurable global hotkey, `ctrl+alt+space` by default
- Menu bar item
- SwiftUI overlay switcher
- One tile per window, across every Space, with a live thumbnail
- Grouping by display, and optionally by Space, under the monitor's own name
- Windows on the current Space come first; minimized windows are restored on
  activation
- Arrow keys move the highlight, Return activates it
- Number keys `1`–`9` activate the first nine tiles directly
- In-memory preview cache only
- CLI commands for debugging and automation

Thumbnails are never written to disk. Preview images live only in process memory.
The only thing Tessera writes is `~/.config/tessera/learned-windows.txt`, and only
when a window fails to come forward.

## Requirements

- macOS 13 or newer
- macOS 14 or newer for window thumbnails (`SCScreenshotManager`); on macOS 13
  the switcher still lists windows and falls back to name-only tiles

## Tile order

What decides the order inside a group, and therefore what makes a tile move:

```toml
window_order = "title"        # the default: application, then window title
window_order = "application"  # application only — a browser tab switch moves nothing
window_order = "stable"       # the order windows were first seen in; nothing moves
```

`title` reads alphabetically but follows what happens inside a window: switch a
browser tab and the title changes, so the tile moves. `application` keeps the
windows of one application in a fixed order between themselves. `stable` hands
each window a place when it first appears — alphabetically, so the first layout is
still sensible — and then leaves it there; a new window is appended at the end.

Grouping still comes first in all three: a display's windows stay together. With
`stable`, switching Spaces no longer reorders anything either, unless Spaces are
what the overlay groups by.

## Leaving applications out

A tray application often keeps its window object alive after you close the
window. From the outside that window is indistinguishable from one on another
Space: same layer, same title, simply not on screen. `SCWindow.isActive` only
repeats `isOnScreen`, Accessibility lists the window either way, and the
activation policy says `regular` for both a tray-only app and an ordinary one.
The only API that knows is the private one this project stays away from.

### Learning it instead

There is one thing that does tell them apart, and it is not a property of the
window but of what happens to it: ask a window to come forward, and a real one
arrives while a leftover does not. Tessera watches that outcome. A window that
was activated and, a second and a half later, is still not on screen — while
still existing — is left out of the switcher from then on.

The cost is one wasted switch per such window, once. There is no way to know
beforehand, and probing windows on its own would throw your desktop around.

What is learned goes to `~/.config/tessera/learned-windows.txt`, one window per
line as application, a tab, and the title. It is written by Tessera and meant to
be read and edited: delete a line to give that window another chance. The lesson
is also dropped by itself the moment such a window turns up on screen, which is
what happens when you open it from the tray again.

Two limits worth knowing. Only the overlay teaches; `tessera focus` activates in
a separate, short-lived process that is gone before the verdict is due. And a
window is recognised by application and title, so a Finder window reopened on the
same folder starts out hidden — until it appears on screen once, which clears it.

### Naming it instead

To leave an application out without waiting to be taught:

```toml
ignored_apps = "AmneziaVPN, Some Tray App"
```

Comma separated, case-insensitive, empty by default.

## Appearance

Tiles can be split into groups along two independent axes, each named group
getting its own heading and its own row:

```toml
ignored_apps = ""
overlay_columns = 4
window_order = "title"
overlay_grouping = "displays"         # the default: one group per monitor
overlay_grouping = "displays+spaces"  # and one per Space within each monitor
overlay_grouping = "spaces"           # split by Space, without naming the monitor
ignored_apps = ""
overlay_columns = 4
window_order = "title"
overlay_grouping = "displays"             # one grid, no headings
```

Splitting by Space splits by display whichever way this is set — a Space belongs
to one monitor — so `spaces` differs from `displays+spaces` only in what the
heading says.

A heading appears only when it distinguishes something: a single monitor is not
named, and a Space is not numbered unless that monitor contributes more than one
group. A group wider than `overlay_columns` wraps onto a second row, so the overlay keeps
fitting the screen:

```toml
overlay_columns = 4   # the default
```

Every group shares one column count, so tiles line up down the overlay rather than
each group choosing its own width.

The overlay paints an opaque matte surface by default — dark enough for the white
tile text, light enough that it does not read as a hole in the screen. It is one
config key:

```toml
overlay_background = "#2B2E33"   # #RRGGBB
overlay_background = "#000000C2" # #RRGGBBAA — an alpha channel lets the desktop through
```

The tiles themselves are painted relative to that surface, so a lighter or darker
background keeps its contrast without further tuning.

## Overlay keys

| Key | Action |
|---|---|
| `←` `→` | Move the highlight one tile, wrapping at the ends of the list |
| `↑` `↓` | Move the highlight one row, crossing into the next group; stops at the top and bottom |
| `Return` `Space` | Activate the highlighted window |
| `1`–`9` | Activate that tile directly |
| A letter | Move to the next window whose name starts with it; press again to cycle |
| `Esc` | Close the overlay without switching |

A letter is read twice: as typed, and as the Latin letter that physical key
carries. On a Cyrillic layout those differ, and an application named in Latin
would otherwise be unreachable by its own initial — pressing the `C` key finds
Code either way.

A letter matches the application name first — `c` walks Claude, then Code, then
back. Only when no application starts with that letter do the window titles get a
turn, which is what makes a letter useful among several Finder windows.

The highlight starts on the window you are in — the one the accent fill marks — so
the arrow keys move away from a known place rather than from wherever the list
happens to begin.

## Displays and Spaces

Tessera lists every window it can switch to, not just the ones on the Space you
are looking at. Tiles are grouped by the display they live on, under that
monitor's own name — `Built-in Retina Display`, `VG27AQL1A`.

Sections follow the way the monitors actually stand: top to bottom, then left to
right. A screen above the laptop gets the upper section. Which display is main,
and which holds the focus, does not enter into it, so the sections stay put
between refreshes. Screens sharing at least half the shorter one's height count
as one row, so a few points of vertical offset between two side-by-side monitors
does not decide their order.

Everything is read fresh on each refresh: a display with no windows gets no
heading, a single-monitor setup gets no headings at all, and unplugging a monitor
simply removes its section on the next pass.

A window belongs to the display covering the largest part of it, the same rule
macOS uses for a window straddling two screens. The frames come from
ScreenCaptureKit rather than `NSScreen`, which matters more than it sounds:
AppKit puts the origin at the bottom left, so pairing its frames with window
frames would mean flipping every rectangle, and a monitor placed above the
built-in display sits at negative coordinates where such mistakes hide well.

With Spaces in `overlay_grouping`, tiles are grouped by Space and the one you are
looking at comes first — so the `1`–`9` shortcuts keep landing on the windows in front of
you. Inside a group the order is by application.

### How the Spaces are worked out

macOS publishes no API for this. `NSWorkspace` will say that the active Space
changed, never which one it is, and a window only reports whether it is on screen
right now. Tools that do know — yabai, AeroSpace — read it out of the private
SkyLight framework, which Apple can change in any update.

Tessera stays on public API and works it out by watching instead. Every window on
screen at one moment shares one Space per display, so each refresh is a membership
set for whichever Space is active. Switching Spaces produces another set, and over
a session the sets add up to a partition of the windows.

That buys correctness at the price of knowledge, and the gaps are worth knowing:

- Spaces are numbered in the order you first visit them, which need not match the
  order Mission Control shows them in.
- A Space you have not visited since Tessera started is unknown. Its windows are
  listed under `Other Spaces` rather than guessed at.
- A minimized window is on no Space as far as this can tell — it is never on
  screen — so it also lands in `Other Spaces`.
- What has been learned is forgotten on restart, and rebuilt as you move around.

`tessera windows` shows no Spaces at all: it is a separate, short-lived process
that has watched nothing. It still groups by display, which needs no history.

Activating a window on another Space switches Spaces, and activating a minimized
window restores it from the Dock first. Both need the Accessibility permission —
without it only the owning application is brought forward.

### Minimized windows

A window in the Dock has no surface, and asking ScreenCaptureKit for its
thumbnail does not fail — it never answers at all. Tessera therefore asks
Accessibility which windows are minimized and skips capturing those, rather than
waiting two seconds on each and then giving up.

A minimized window keeps whatever preview was captured before it went to the
Dock. One that was already minimized when Tessera started has none, and its tile
shows the application icon and the word `Minimized`. Activating it restores the
window first, then raises it.

Telling minimized apart from off-screen needs Accessibility. Without that
permission both look the same, and minimized windows fall back to the old
behaviour: one slow capture attempt, then a name-only tile.

Thumbnails are captured for windows on other Spaces too. A window whose app has
stopped rendering may never answer a capture at all; Tessera gives up on it after
two seconds, shows a name-only tile, and stops asking that window for five
minutes rather than stalling the refresh loop.

## Permissions

Tessera needs two permissions, and degrades in a defined way without them:

| Permission | Needed for | Without it |
|---|---|---|
| Screen Recording | Listing windows, capturing thumbnails | The overlay is empty |
| Accessibility | Raising one specific window | Only the owning application is brought forward |

Check the current state at any time:

```sh
tessera permissions
```

Grant them in System Settings > Privacy & Security. The menu bar item also offers
"Grant Accessibility Permission…" while that permission is missing.

## Build

```sh
make build
make build CONFIG=release
```

The local convenience binary can point at the release build:

```sh
ln -sf "$PWD/.build/release/Tessera" ~/.local/bin/tessera
```

## Run The Background App

```sh
swift run Tessera run
```

Or, after a release build:

```sh
tessera run
```

The app stays alive in the background. Closing the overlay does not quit the app.

`run` is idempotent: if a background instance is already running, the new `run`
process exits without creating a second menu bar item or a second preview service.

## CLI

```sh
tessera run
tessera show
tessera toggle
tessera quit
tessera restart
tessera windows
tessera focus 12345
tessera permissions
```

Primary lifecycle commands:

- `run` starts the background app if it is not already running.
- `show` shows the window switcher overlay in the running background app.
- `toggle` toggles overlay visibility.
- `quit` asks the running background app to stop cleanly.
- `restart` asks the running background app to stop, then launches a fresh `run`.

Debug / utility commands:

- `windows` lists switchable windows as
  `<id>\t<app>: <title>\t(<display>[, off-screen | minimized])`
- `focus <id>` brings the window with that id to the front
- `permissions` reports Screen Recording and Accessibility status

`show`, `toggle`, `quit`, and `restart` talk to the running background app through
`DistributedNotificationCenter`.

Current notification contract:

- show name: `com.tessera.show-switcher`
- toggle name: `com.tessera.toggle-switcher`
- quit name: `com.tessera.quit-app`
- object: `com.tessera`
- receiver suspension behavior: `deliverImmediately`

## Lifecycle

Tessera uses an app-level `flock` guard at:

```text
~/.config/tessera/tessera.lock
```

Only the long-running `run` process holds this lock. Sender commands such as
`show`, `toggle`, `quit`, and `restart` do not acquire it as long-running app
instances.

This keeps repeated launches safe:

- first `tessera run` starts the background app
- second `tessera run` exits without creating a duplicate
- `tessera restart` is the explicit command for controlled replacement
- `tessera quit` stops refresh tasks, clears the in-memory preview cache, removes
  observers, and terminates the app

## Hotkey

`ctrl+alt+space` toggles the overlay. The binding is registered by the background
app itself through `RegisterEventHotKey`, so it needs no Accessibility permission
and it consumes the key press rather than passing it to the focused app.

Change it in the config:

```toml
hotkey = "cmd+shift+space"
```

- At least one modifier is required. A bare key would be swallowed system-wide.
- Modifiers: `ctrl`, `alt`, `shift`, `cmd` (`control`, `option`/`opt`, `command`
  also work).
- Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `space`, `tab`, `return`, `escape`,
  `delete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`.
- Key names are physical positions on a QWERTY layout, not the characters your
  current layout produces.
- `hotkey = ""` disables it. Then bind `tessera toggle` in a launcher instead.

If another application already owns the combination, registration fails, the app
logs the failure and keeps running — the menu bar item and the CLI still work.

## Config

Example config:

```sh
cp config.example.toml ~/.config/tessera/config.toml
```

If the config file is missing or partially invalid, the app falls back to defaults.

Useful settings:

```toml
refresh_interval_seconds = 3
window_thumbnails_stale_seconds = 30

dim_stale_thumbnails = false
window_thumbnail_target_width = 240
window_thumbnail_target_height = 160
max_windows = 24

hotkey = "ctrl+alt+space"

ignored_apps = ""
overlay_columns = 4
window_order = "title"
overlay_grouping = "displays"
overlay_background = "#2B2E33"

close_after_activation = true
show_menu_bar_icon = true
debug_mode = false
```

## Logs

```sh
log stream --info --debug --predicate 'subsystem == "com.tessera"'
```

Useful source markers:

- `global_hotkey`
- `menu_bar_action`
- `external_show_command`
- `external_toggle_command`
- `external_quit_command`
- `external_restart_command`
- `internal_activation`
- `unexpected_external_trigger`

## Design notes

`docs/mechanisms.md` explains why the non-obvious parts work the way they do —
window enumeration, display and Space resolution, the capture that never returns,
minimized windows, leftover tray windows — including what was measured and which
approaches were tried and rejected.

## Project Structure

```text
docs/mechanisms.md                   Why the non-obvious parts work as they do

Sources/Tessera/
  AppConfig.swift                    Runtime configuration model
  AppConfigLoader.swift              TOML config loading
  AppCoordinator.swift               App lifecycle and trigger routing
  AppEntry.swift                     CLI/GUI entrypoint
  AppLogger.swift                    OSLog wrapper
  BackgroundAppNotifications.swift   Distributed notification contract
  DisplayInfo.swift                  Which display a window sits on
  CLI.swift                          CLI commands
  HotkeyBinding.swift                Hotkey spec parsing and Carbon key codes
  HotkeyController.swift             Global hotkey registration
  MenuBarController.swift            Menu bar integration
  LearnedWindowStore.swift           Windows that ignored an activation
  MinimizedWindowService.swift       Which windows are in the Dock
  Models.swift                       Shared models
  OverlayColor.swift                 Hex colour parsing for the overlay surface
  OverlayGrid.swift                  Arrow-key navigation over the tile grid
  OverlayGrouping.swift              Whether the overlay groups by Space
  OverlayView.swift                  SwiftUI switcher UI
  OverlayWindowController.swift      Native overlay window
  SingleInstanceLock.swift           Background app single-instance guard
  SpaceTracker.swift                 Learns which windows share a Space
  WindowOrder.swift                  Tile order and the places it hands out
  WindowActivator.swift              Window focus via NSRunningApplication + Accessibility
  WindowCoordinator.swift            Window list and thumbnail refresh pipeline
  WindowListService.swift            ScreenCaptureKit window enumeration
  WindowPreviewCache.swift           In-memory thumbnail cache
  WindowThumbnailService.swift       ScreenCaptureKit window thumbnails

Tests/TesseraTests/
  ActivationVerifierTests.swift          Judging what an activation did
  AppConfigLoaderTests.swift             Config parsing and fallback to defaults
  BackgroundAppNotificationsTests.swift  Distributed notification contract
  HotkeyBindingTests.swift               Hotkey spec parsing, aliases, rejections
  DisplayInfoTests.swift                 Window-to-display resolution and ordering
  LearnedWindowStoreTests.swift          Reading and writing what was learned
  MinimizedWindowServiceTests.swift      Minimized-window lookup
  ModelsTests.swift                      Tile fallbacks, identity, display sections
  OverlayColorTests.swift                Hex colour parsing
  OverlayGridTests.swift                 Row layout and arrow-key movement
  OverlayGroupingTests.swift             Grouping setting parsing
  SingleInstanceLockTests.swift          flock contention and release
  SpaceTrackerTests.swift                Learning, merging and forgetting Spaces
  WindowOrderTests.swift                 Order parsing and place assignment
  WindowPreviewCacheTests.swift          Thumbnail storage, staleness, eviction
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

## TODO

- Let the menu bar item show the current hotkey and report a failed registration,
  which today only reaches the log.
- Cover `WindowCoordinator` and the ScreenCaptureKit services; they take
  concrete collaborators today, so testing them needs protocols first.
