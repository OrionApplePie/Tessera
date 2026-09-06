# Keys

Every key the overlay answers to, and the one that opens it. The settings
window carries the same list under **Keys**, with the two that are settings
shown as they are actually bound.

## Overlay keys

Every combination is written with a plus between its keys, modifiers included,
and a key that has a name is called by it — `Return`, `Delete`, `Tab` — rather
than by a symbol. The settings window's **Keys** page says the same thing the same
way, and shows the two that are settings as they are actually bound.

| Key | Action |
|---|---|
| `←` `→` | Move the highlight one tile, wrapping at the ends of the list |
| `↑` `↓` | Move the highlight one row, crossing into the next group; stops at the top and bottom |
| `Return`, `Space` | Switch to the highlighted window and close the overlay |
| `1` – `9` | Activate that tile directly |
| A letter | Move to the next window whose name starts with it; press again to cycle |
| `Tab`, `⇧ + Tab` | The next and previous window inside a Space |
| `⇧ + arrows` | Move the highlighted tile itself, within its group |
| `⌘ + arrows` | Send the highlighted window to the display the arrow points at |
| `⌥ + arrows` | Put the highlighted window in that half of its screen |
| `⌘ + Return` | Fill the screen with the highlighted window |
| `⌘ + F` | Hand the window to its application's own fullscreen mode |
| `⌃ + ⌥ + ⇧ + arrows` | Switch to the window in that direction, keeping the overlay up |
| `⌘ + \` | Play or pause what the highlighted window's application is playing |
| `⌘ + ]`, `⌘ + [` | Next and previous, for the same |
| `⌘ + W` | Close the highlighted window — by default this quits its application |
| `⌘ + N` | Add a desktop to the display the highlight is on |
| `⌘ + Delete` | Close the Space under the highlight, if nothing is on it |
| `Esc` | Close the overlay without switching |

`Delete` is the key marked *delete* on a Mac keyboard — backspace, the one above
the backslash — not the forward delete of a full-size board.

`Esc`, `Return` and `Space` keep working after a step has given the keyboard to
another application: they are held system-wide for as long as the overlay is up,
and released the moment it closes.

A key means every letter printed on it, across the keyboard layouts you have
enabled. Pressing the `C` key finds Code whatever layout is active, and on a Mac
with a Russian layout installed it also finds Windows named in Cyrillic with `С` —
without switching layout first. What you actually typed is tried first, then the
Latin letter of that key, then what the other layouts make of it.

A letter matches the application name first — `c` walks Claude, then Code, then
back. Four passes, in this order: the application's whole name, a word inside it,
the window's whole title, a word inside that. So `e` finds Excel even though its
application is called "Microsoft Excel", and does so only once nothing simpler
answers to `e` — which is what keeps a letter meaning the obvious thing.

Typing can search instead of jumping:

```toml
overlay_search = "letter"   # the default: a letter walks the windows of that name
overlay_search = "fuzzy"    # letters build a query, scored as you type
```

`fuzzy` scores what is typed against the application, the window title and the
heading of the Space — weighted in that order — the way `fzf` does: letters need
not be adjacent, but the start of a word beats the middle of one and letters
running together beat letters scattered. A Space with nothing on it is found by
its heading, so `desktop 3` reaches an empty desktop. What is typed is shown in a
line under the overlay, `Backspace` takes a letter back, and `Esc` clears it before it
closes anything.

`⌃⌥⇧` with an arrow steps through the windows and switches to each one as it goes,
leaving the overlay up, and the overlay travels to the display the window is on
rather than staying behind — a tiling window manager's directional movement, as
close as macOS allows. It is the overlay that stands in for them, because macOS has no
geometric arrangement of Spaces to navigate.

Stepping is for finding a window by looking at it rather than at its
thumbnail. The overlay stops hiding itself for the duration and takes the keyboard
straight back after each switch, so the next step still reaches it.

Tiles can also be arranged by hand — with `⇧` and the arrow keys, or by dragging
one onto another. Within a display that moves the thumbnail and nothing else: the
window itself stays where it is.

Dropping a tile on another display's group, or pressing `⌘` with an arrow, moves
the window itself. A window belongs to whichever display covers most of it, so
this is its rectangle being put on the other screen: it keeps its place in
proportion — a window against the right edge arrives against the right edge — and
is taken down to fit only if it is too large for the screen it arrives on. With
displays keeping separate Spaces, it lands on whatever Space the other display is
showing.

A tile whose application is putting sound out is marked with a speaker, and the
three keys above act on it. A player that is merely open — Spotify sitting there
paused — is started too. Spotify, Music, TV and VLC are asked directly where macOS
allows it, and where it does not — a binary without an app bundle is refused
permission to send Apple events, silently — the media key is sent instead, which
starts whichever player was last playing. What is playing cannot be shown — since macOS 15.4
the now-playing information needs an entitlement Apple does not hand out — so the
mark says that something is playing and no more. The keys are the ordinary media
keys, which macOS routes to whatever it considers the application that is
playing; pressed at a window that is silent they would reach something else, so
they are refused there and the log says why.

`⌥` with an arrow tiles by geometry rather than by asking the application: the
window takes that half of the screen its display leaves free, so two windows put
side by side meet exactly. `⌘⏎` is the same thing for the whole screen. `⌘F` is
different in kind — fullscreen is a mode, not a rectangle, so it is the
application that does it, and the window gets a Space of its own.

Between Spaces of one display, no. macOS has no public way to move a window to
another Space, and on macOS 15 the private ones do nothing either; `docs/
mechanisms.md` records what was tried. A window Accessibility will not list —
Finder's windows, and any window on a Space that is not showing — cannot be moved
either, and says so rather than failing quietly.

The first such move outranks `window_order` for the rest of the session, since an
order made by hand is not one a sort should undo. It is forgotten on restart:
window identifiers change, so there is nothing to pin an arrangement to.

The highlight starts on the window you are in — the one the accent fill marks — so
the arrow keys move away from a known place rather than from wherever the list
happens to begin.

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
