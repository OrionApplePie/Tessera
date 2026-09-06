# Tessera

Native macOS window switcher: one overlay with every window on every Space, laid
out the way the displays actually stand.

It runs as a background menu bar utility, keeps window previews in RAM, and needs
no external tool — windows are found through ScreenCaptureKit and raised through
`NSRunningApplication` and the Accessibility API, all public macOS frameworks.

- [Install](#install)
- [Requirements](#requirements)
- [Permissions](#permissions)
- [What it does](#what-it-does)
- [Keys](#keys)
- [Language](#language)
- [What things are called](#what-things-are-called)
- [Everything else](#everything-else)
- [Licence, and no warranty](#licence-and-no-warranty)

## Install

With Homebrew, from this project's own tap:

```sh
brew tap OrionApplePie/tessera
brew install tessera
```

That builds the latest tagged release; `brew install --HEAD tessera` builds
whatever `main` is instead.

Then start it, and keep it starting at login:

```sh
brew services start tessera
```

Or run it from a terminal instead — `tessera run` — which is the better way while
granting permissions, because macOS attributes the prompts to whatever started the
binary. It holds that terminal for as long as it runs, so the service above is the
everyday answer. `tessera permissions` says what is still missing.

The formula lives here at `Formula/tessera.rb` and is copied into the tap; the tap
is a repository of its own, called `homebrew-tessera`, because that is the name
`brew tap` looks for.

## Requirements

- macOS 13 or newer
- macOS 14 or newer for window thumbnails (`SCScreenshotManager`); on macOS 13 the
  switcher still lists windows and falls back to name-only tiles

## Permissions

Two, and each has a defined degraded mode:

| Permission | Needed for | Without it |
|---|---|---|
| Screen Recording | Listing windows, capturing previews | The overlay is empty |
| Accessibility | Raising one particular window | Only the owning application comes forward |

`tessera permissions` says which are granted. Both are granted in System Settings
› Privacy & Security; the menu bar item offers "Grant Accessibility Permission…"
while that one is missing.

## What it does

- One tile per Space, across every display, with a live preview of each window
- Groups by display and by Space, under the monitor's own name
- Arrows move the highlight, `Return` takes it, `1`–`9` pick a tile outright
- Typing jumps to a window by name, or searches, as you prefer
- Sends a window to another display, to half a screen, or to fullscreen
- Adds and closes desktops, which macOS itself offers no other program a way to do
- Plays, pauses and steps through whatever the highlighted window is playing
- Previews live in memory only, and are never written to disk

The one file it writes is `~/.config/tessera/learned-windows.txt`, and only when a
window fails to come forward — see [docs/settings.md](docs/settings.md).

## Keys

`⌃⌥Space` opens the overlay; hold `⌃⌥` and press an arrow to step through windows
and switch when the keys are let go.

| Key | What it does |
|---|---|
| arrows | Move the highlight |
| `Return`, `Space` | Switch to what is highlighted |
| `1`–`9` | Pick that tile |
| a letter | Jump to a window by name |
| `⌘` + arrows | Send the window to that display |
| `⌘N`, `⌘⌫` | Add a desktop, close an empty one |
| `Esc` | Close the overlay |

The rest — placing a window in half a screen, fullscreen, playback, closing a
window — is in [docs/keys.md](docs/keys.md), and in the settings window under
**Keys**, where the two shortcuts that are settings are shown as they are bound.

## Language

The interface is English and Russian and follows the system: `ru-RU` at the top of
your language list gets Russian, anything else gets English. The switcher says
which it chose in its log at startup, because a program speaking the wrong
language is hard to argue with otherwise.

The command line and the logs stay English — they are read by scripts and pasted
into reports.

Adding a language is two steps: copy `Sources/TesseraKit/en.lproj` to
`<language>.lproj`, translate the right-hand side of each line, and run
`make strings`, which lists anything the code asks for that the new file does not
have yet.

## What things are called

The window that appears is the **overlay**; each Space on it is a **section**; a
window inside one is a **tile**; several tiles shown as a stack are a **deck**.
[docs/glossary.md](docs/glossary.md) has the full list, with the Russian words
beside them and the names the code uses.

## Everything else

| | |
|---|---|
| [docs/keys.md](docs/keys.md) | every key, and the global hotkey |
| [docs/settings.md](docs/settings.md) | what a tile shows, appearance, grouping, order, timing, the settings window, the config file |
| [docs/spaces.md](docs/spaces.md) | displays and Spaces: what is known, what is learned, what macOS refuses |
| [docs/cli.md](docs/cli.md) | the commands, running the background app, its lifecycle and log |
| [docs/development.md](docs/development.md) | building, the source layout, the tests, what is left to do |
| [docs/glossary.md](docs/glossary.md) | what things are called, in Russian, in English and in the code |
| [docs/mechanisms.md](docs/mechanisms.md) | why the non-obvious parts work as they do, and what was measured |
| [docs/packaging.md](docs/packaging.md) | how it is installed, and what a release needs |

## Licence, and no warranty

GNU General Public License v3.0 or later. The full text is in `LICENSE`.

This is a personal tool published in the hope it is useful. It comes **as is**,
with no warranty of any kind, express or implied — no fitness for any purpose, no
promise that it will keep working after the next macOS update, and no support
owed. It drives undocumented corners of macOS on purpose, and the ones that are
documented change; if it breaks something, you keep both halves. Nobody is liable
for anything it does or fails to do.
