# Settings

What can be changed, what each setting costs, and where it is written down.
Everything here is also in the settings window: `tessera settings`.

- [What a tile shows](#what-a-tile-shows)
- [Appearance](#appearance)
- [Groups](#groups)
- [Tile order](#tile-order)
- [Timing](#timing)
- [Closing from the overlay](#closing-from-the-overlay)
- [Leaving applications out](#leaving-applications-out)
- [Reaching a particular window](#reaching-a-particular-window)
- [Settings window](#settings-window)
- [Config](#config)

## What a tile shows

```toml
window_thumbnail_mode = "75"        # the default: three quarters of the window
window_thumbnail_mode = "fit"       # the whole window, scaled down
window_thumbnail_mode = "corner"    # its top left corner, at actual size
window_thumbnail_mode = "corner2x"  # twice as much corner, at half size
window_thumbnail_mode = "quarter"   # roughly a quarter of the window
```

A long window is captured and drawn whole whatever the mode says, because a crop
keeps the shape of the space the picture is drawn in — and that space is
landscape. A window lying across it keeps almost nothing: measured, a settings
window at 560 by 784 points and a player at 338 by 612 lose everything but their
top, while an editor at 1512 by 944 lies the same way as the picture and keeps
enough. The measurement is against that space, at a ratio of 1.5, so it catches a
very wide window as well as a tall one.

A window that is not on screen keeps the preview it already had, so one of these
shows its old cropped picture until its Space has been visited once.

```toml
window_thumbnail_whole_when_long = true   # the default
window_thumbnail_whole_when_long = false  # crop those too, like everything else
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
asked for is taken whole.

How many pixels a `fit` capture gets is not a number anybody types: the overlay sizes
its tiles from the screen and from how many Spaces there are, so the capture is
made for the largest tile the overlay may draw. `window_thumbnail_quality` is the
knob for wanting more than that.

## Appearance

Tiles can be split into groups along two independent axes, each named group
getting its own heading and its own row:

```toml
overlay_grouping = "displays+spaces"  # the default: a group per Space, per monitor
overlay_grouping = "displays"         # one group per monitor
overlay_grouping = "spaces"           # split by Space, without naming the monitor
overlay_grouping = "none"             # one grid, no headings
```

Splitting by Space splits by display whichever way this is set — a Space belongs
to one monitor — so `spaces` differs from `displays+spaces` only in what the
heading says.

A heading appears only when it distinguishes something: a single monitor is not
named, and a Space is not numbered unless that monitor contributes more than one
group. A group wider than `overlay_columns` wraps onto a second row, so the overlay keeps
fitting the screen:

```toml
overlay_columns = 7   # the default, and only the fixed arrangement is told it
```

Every group shares one column count, so tiles line up down the overlay rather than
each group choosing its own width.

`overlay_columns` is the shape of one layout only. `overlay_layout` says which:

```toml
overlay_layout = "flow"     # the default: no bands, wraps when the row is full
overlay_layout = "fitted"   # the same search, but each display keeps its own rows
overlay_layout = "count"    # a square: four Spaces go two by two, nine three by three
overlay_layout = "rows"     # exactly overlay_columns across
```

`flow` and `fitted` both try every row length and keep the one that makes the
largest tile. They differ in one thing: `fitted` starts a new row where the
display changes, so each screen's Spaces read as a block, and `flow` does not —
the Spaces run on in the order the displays are arranged, a monitor above the
laptop first, and the row breaks only when it is full. That fits more on the overlay
at a larger tile, and the heading is then what says which display a Space is on.

The two numbers that apply to all of them are a ceiling and a floor:

```toml
overlay_max_cells = 24   # at most this many Spaces on the overlay, shared between displays
overlay_min_tile = 150   # points; what will not fit at this size is left off
```

A cell is what stands beside its neighbour — a Space when its windows are stacked,
a window when they are fanned out. The ceiling is shared out between the displays
rather than spent first-come, so one busy screen cannot crowd the other off the
overlay, and the Space you are on is charged to it rather than added on top. The floor
is what stops the answer to "one more Space" being "every tile a little smaller":
past it the overlay leaves Spaces off instead.

The overlay paints an opaque matte surface by default — dark enough for the white
tile text, light enough that it does not read as a hole in the screen. It is one
config key:

```toml
overlay_background = "#2B2E33C2" # the default: #RRGGBBAA, the alpha lets the desktop through
overlay_background = "#2B2E33"   # #RRGGBB — a solid panel
```

The tiles themselves are painted relative to that surface, so a lighter or darker
background keeps its contrast without further tuning.

## Groups

With `overlay_grouping = "displays+spaces"` each Space is drawn as a block of its
own — a framed group with its windows inside — and the groups are laid out left to
right, wrapping to another row when they run out of width. A heading alone left the
eye to work out where one Space ended and the next began; a frame says it.

Which Space a window is on comes from the window server when
`use_private_space_api` allows it, and from what has been seen on screen together
when it does not.

The windows of a Space are stacked, not spread out: one card on top, a mark saying
how many are behind it, and a turn of the card as you step through them. A Space
then takes the room of one window however many it holds, which is what keeps an overlay
of a dozen Spaces readable. `overlay_deck = "fan"` spreads them instead, each card
peeking out from behind the one in front of it.

Choosing a Space rather than a window — the only way onto a desktop with nothing on
it — presses the shortcut macOS binds to that desktop, the same ⌃1…⌃8 you would
press yourself. It follows that a desktop whose shortcut you have switched off in
System Settings > Keyboard > Shortcuts > Mission Control cannot be reached from the
overlay either, and that a fullscreen Space is reached by its window rather than as
a Space, since macOS numbers only desktops.

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

Comma separated, case-insensitive, empty by default. This one names applications,
whatever kind they are.

### Leaving out a whole kind

```toml
ignore_menu_bar_apps = true
```

Off by default, and a different question from the field above: rather than naming
an application, this leaves out every application with no Dock icon. That is what
AppKit calls an `.accessory` activation policy and what people call living in the
menu bar. Their windows are panels they put up themselves rather than places to
switch to, and Accessibility commonly will not raise them at all — a tile for one
is a tile that does nothing.

It is not a cure for the leftover window above: an application that keeps a closed
window alive is usually `regular` all the same, and stays listed.

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

## Settings window

`tessera settings`, or `Settings…` in the menu bar, opens a window with every
setting in it. `Save and Restart` writes the file and replaces the running
background app with one that has read it.

Its pages are **App**, **Layout**, **Appearance**, **Timing**, **Keys** and
**About**. Keys lists everything the overlay answers to, with the two shortcuts
that are settings shown as they are actually bound — a switcher is used with the
hands and read about once, so the list belongs in the window rather than only
here. `Restore Defaults` fills the form with what Tessera ships with and stops
there: nothing is written until you save, so the defaults can be read off the
pages and then cancelled.

Some controls apply only in some arrangements, and say so by greying out rather
than by doing nothing: the row length is listened to by the fixed arrangement
alone, and the arrangement itself only while the overlay grows into the screen.

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

dim_stale_thumbnails = true
max_windows = 24

hotkey = "ctrl+alt+space"
close_hotkey = "cmd+w"
close_action = "quit"

ignored_apps = ""
ignore_menu_bar_apps = false
overlay_columns = 4
window_order = "title"
overlay_grouping = "displays"
overlay_background = "#2B2E33C2"

show_menu_bar_icon = true
debug_mode = false
```
