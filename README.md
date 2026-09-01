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

## What a tile shows

```toml
window_thumbnail_mode = "fit"       # the default: the whole window, scaled down
window_thumbnail_mode = "corner"    # its top left corner, at actual size
window_thumbnail_mode = "corner2x"  # twice as much corner, at half size
window_thumbnail_mode = "quarter"   # roughly a quarter of the window
```

`fit` says what shape a window is and where things sit in it, which is enough to
tell two applications apart. It is not enough to tell two documents apart: a
window scaled into a tile turns its text into grey texture.

The other three fill the same tile with the window's top left corner instead, and
differ only in how much of it. `corner` is the tile's own area at 1:1 — the
sharpest, and the least of the window. `corner2x` takes twice that across and
down, drawn at half size, which stays legible on a Retina display. `quarter` takes
about a quarter of the window's area, enough to recognise a document by its layout.

All three keep the tile's proportions, so the top left corner is what actually
reaches the screen rather than the middle of a wider crop, and all three are
captured through ScreenCaptureKit's `sourceRect` rather than cropped afterwards —
a large window costs no more than a small one. A window smaller than the piece
asked for is taken whole. `window_thumbnail_target_width` and `..._height` apply
to `fit` only.

## Timing

Everything the switcher waits for is a setting, because every one of these numbers
is a compromise measured on one desktop rather than a value with a right answer:

```toml
activation_settle_seconds = 1.5   # how long the system gets to finish a switch
unresponsive_after_seconds = 2    # how long anything gets to answer at all
```

Neither is a polling interval. Nothing is polled: macOS announces a Space change
and an application coming forward, and the switcher asks again when it hears one.
`activation_settle_seconds` is only where waiting stops — a window that has not
appeared by then is one that is not coming. It is deliberately longer than a Space
switch and its animation, because a window judged before it lands is recorded as
one that refused to come, and gets left out of the switcher.

`unresponsive_after_seconds` covers everything that can simply not answer: a
window asked for a preview, an application asked an Accessibility question. A
window that misses it is left alone until it comes back on screen, which is when
it has a surface to capture again — there is no cooldown to tune, because there is
no guess to make.

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

## Closing from the overlay

The close shortcut can end the whole application or shut a single window:

```toml
close_hotkey = "cmd+w"   # "" turns the shortcut off
close_action = "quit"    # or "window"
```

`quit` asks the application to quit, the way ⌘Q does — it still gets to prompt
about unsaved work. It is the default because an application that keeps running
with its window closed is how a leftover window is made, and those are the ones
this switcher cannot tell from a window on another Space.

`window` presses the window's own close button and leaves the application running.
That needs Accessibility, and it cannot reach a window Accessibility does not
list — Finder's, for one. Quitting has neither limitation.

It acts on the highlighted tile, and the highlight is worked out as the overlay
opens rather than taken from the last background refresh. That distinction is not
academic: before it was fixed, this shortcut asked the wrong application to quit.

## Reaching a particular window

Choosing a tile brings its application forward, which is enough to cross Spaces.
Landing on the *right* window of several takes more, because Accessibility lists
only the windows on the Space that is active — so at the moment you choose, the
window usually cannot be named yet.

Tessera asks Accessibility first. When it cannot aim — the window is on another
Space, or the application publishes no windows at all, as Finder and Chrome do not
— it presses the window's entry in the application's own Window menu, which is the
only public list that names a window across Spaces. Failing both, it waits for the
system to announce that a Space has changed or an application has come forward,
and asks Accessibility again.

An application that lists nothing in its Window menu and keeps the window you want
on another Space cannot be reached precisely by any public means.
`docs/mechanisms.md` has the measurements.

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
| `⇧` + arrows | Move the highlighted tile itself, within its group |
| `⌃⌥⇧` + arrows | Switch to the window in that direction, keeping the overlay up |
| `⌘W` | Close the highlighted window — by default this quits its application |
| `Esc` | Close the overlay without switching, even after a step took the keyboard |

A key means every letter printed on it, across the keyboard layouts you have
enabled. Pressing the `C` key finds Code whatever layout is active, and on a Mac
with a Russian layout installed it also finds Windows named in Cyrillic with `С` —
without switching layout first. What you actually typed is tried first, then the
Latin letter of that key, then what the other layouts make of it.

A letter matches the application name first — `c` walks Claude, then Code, then
back. Only when no application starts with that letter do the window titles get a
turn, which is what makes a letter useful among several Finder windows.

`⌃⌥⇧` with an arrow steps through the windows and switches to each one as it goes,
leaving the overlay up, and the overlay travels to the display the window is on
rather than staying behind — a tiling window manager's directional movement, as
close as macOS allows. It is the overlay that is the map, because macOS has no
geometric arrangement of Spaces to navigate.

Stepping is for finding a window by looking at it rather than at its
thumbnail. The overlay stops hiding itself for the duration and takes the keyboard
straight back after each switch, so the next step still reaches it.

Tiles can also be arranged by hand — with `⇧` and the arrow keys, or by dragging
one onto another. That moves the thumbnail and nothing else: the window itself
stays where it is, and an arrangement cannot cross into another display's group,
which would put a thumbnail under a heading it does not belong to.

The first such move outranks `window_order` for the rest of the session, since an
order made by hand is not one a sort should undo. It is forgotten on restart:
window identifiers change, so there is nothing to pin an arrangement to.

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
tessera settings
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
- `settings` opens the settings window.
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
hotkey = "alt+tab"
```

- At least one modifier is required. A bare key would be swallowed system-wide.
- Modifiers: `ctrl`, `alt`, `shift`, `cmd` (`control`, `option`/`opt`, `command`
  also work).
- Keys: `a`–`z`, `0`–`9`, `f1`–`f12`, `space`, `tab`, `return`, `escape`,
  `delete`, `left`, `right`, `up`, `down`, `home`, `end`, `pageup`, `pagedown`.
- Key names are physical positions on a QWERTY layout, not the characters your
  current layout produces.
- `hotkey = ""` disables it. Then bind `tessera toggle` in a launcher instead.

Pick a combination nothing else owns, and prefer checking rather than assuming:

- If another application already holds it, registration fails, the app logs the
  failure and keeps running — the menu bar item and the CLI still work.
- If **macOS** holds it, registration *succeeds*, both claims stand, and the key
  goes to whichever asked for it last. The overlay then opens for hours and
  stops without a word. Tessera reads the system's own shortcut list at startup
  and logs a warning naming the one it collides with; `ctrl+alt+space` is also
  "Select the next source in the Input menu", so on a Mac with two keyboard
  layouts either switch that off in System Settings > Keyboard > Keyboard
  Shortcuts, or bind something else. The tab key carries no system shortcut at
  all, which makes `alt+tab` a safe choice.

## Settings window

`tessera settings`, or `Settings…` in the menu bar, opens a window with every
setting in it. `Save and Restart` writes the file and replaces the running
background app with one that has read it.

Two things worth knowing before using it:

- The file is **regenerated whole**. The parser here reads a subset of TOML and
  has no notion of where a value sat or what was written around it, so comments
  and ordering added by hand do not survive a save.
- Changes take effect through a restart, not live. The configuration is read once
  at launch and handed to the services as values; making it apply live would mean
  turning it into a shared, observed source — a change to how the app is wired
  rather than to this window.

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
close_hotkey = "cmd+w"
close_action = "quit"

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

- Tell a window an application no longer owns from one on another Space. Nothing
  public distinguishes them — see `docs/mechanisms.md`; the Window menu may, since
  it lists what the application still considers a window.

- Let the menu bar item show the current hotkey and report a failed registration,
  which today only reaches the log.
- Cover `WindowCoordinator` and the ScreenCaptureKit services; they take
  concrete collaborators today, so testing them needs protocols first.
