# Displays and Spaces

How the switcher works out which Space a window is on, what it can do to a
Space, and what macOS does not allow.

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

### Adding and closing a desktop

`⌘ + N` adds a desktop to the display the highlight is on. Mission Control appears
for about a second while it happens, because Mission Control's own buttons are what
get pressed: macOS keeps its calls for making and unmaking Spaces to itself, and
reaching them the way window managers do means turning off part of System Integrity
Protection. This route needs nothing beyond the Accessibility permission Tessera
already asks for.

#### Closing an empty one

An empty Space is a section of the overlay with no tiles in it, headed by its own
name — `Desktop 4`. The highlight stands on the section itself there, since there
is nothing inside it to stand on, and that is the thing `⌘ + Delete` closes:

1. Open the overlay with `⌃⌥Space`.
2. Move the highlight onto the empty Space with the arrow keys, or reach it by
   typing its name — `desktop 4` — with `overlay_search = "fuzzy"`.
3. Press `⌘ + Delete`. `Delete` is the key marked *delete*, the backspace one.

The overlay goes away, Mission Control flashes for about half a second, and the
desktop is gone. Nothing happens, and the log says why, in three cases: the
highlight is on a window rather than on an empty Space, the Space still has windows
on it, or it is the only desktop that display has — macOS will not remove the last
one.

Closing is offered only for a Space with nothing on it. A Space with windows closes
just as readily and macOS moves those windows to the neighbouring Space — too large
a thing to happen from one keystroke, and the overlay cannot show it before it is
done. To close one anyway, empty it first, or use Mission Control itself.

From the command line the same two actions carry no such rule, and an index may be
given explicitly:

```sh
tessera space list          # the Spaces of the display in use, with their indexes
tessera space add           # one more desktop
tessera space close         # the current Space
tessera space close 4       # that one, windows or no windows
```

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
