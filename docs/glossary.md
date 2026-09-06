# What things are called

The same things live in three places at once: in conversation, in the interface
and in the code. This is what each of them calls what, so that «плитка» in a
message, `tile` in a source file and the word in the settings window all mean one
thing.

One rule: **a thing has one name**. The overlay is always the overlay, never "the
map"; a tile is always a window, never "a card".

- [Words](#words)
- [The entities in the code](#the-entities-in-the-code)
- [How a deck is drawn](#how-a-deck-is-drawn)
- [Where each subject lives](#where-each-subject-lives)

## Words

| In English | По-русски | What it is |
|---|---|---|
| **overlay** | оверлей | The switcher's window as a whole: what appears on ⌃⌥Space. |
| **space**, **desktop** | спейс, рабочий стол | A macOS desktop. A fullscreen window is a Space too — its own. |
| **section** | секция | One Space on the overlay, with windows or empty. |
| **tile** | плитка | One window of an application. It lives inside a section. |
| **deck**, **group** | колода, группа | Several tiles of one section drawn as a stack. Not an entity — a way of drawing. |
| **screenshot**, **preview** | скриншот, снимок | The picture of a window drawn on its tile. |
| **highlight** | выделение | Where the keyboard is: on a tile, or on an empty section. |

## The entities in the code

There are two. Everything else is either machinery or drawing.

| Type | What it is | What it holds |
|---|---|---|
| `SpaceSection` | a **section** — one Space of one display | `id`, `title`, `tiles`, `isCurrent`, `isFullscreen`, `targets` |
| `WindowTile` | a **tile** — one window | `id` (the window number), `appName`, `title`, `processID`, `displayID`, `spaceIndex`, `thumbnail`, `isActive`, `isMinimized`, `isSounding` |

Beside them:

| Type | What it is |
|---|---|
| `SpaceSectionID` | a section's address: display and Space number. Sections are recognised across refreshes by it |
| `DiscoveredWindow` | a window as the system reported it, before it becomes a tile |
| `OverlayTarget` | what the highlight can stand on: `.window(tile)` or `.space(section)` — an empty Space is a place you can go to as well |
| `WindowSnapshot` | the whole window list as one enumeration returned it |

**There is no type for a group**, and no reason to add one: it would carry no
field a section does not have. It exists only in the drawing — `WindowGroup` draws
a section's frame and heading, `WindowDeck` lays out its tiles. A section takes
one cell of room in every style: the fan shrinks its own tiles to fit the room of
one.

## How a deck is drawn

Three styles, differing in what happens on the way to the next tile.

| In English | По-русски | In the code | What you see |
|---|---|---|---|
| **flip** | флип | `OverlayDeckStyle.stack`, `WindowDeck.stacked` | One tile over the rest, with a count beside the heading. A step turns it over. The default. |
| **fan** | тусовать | `.fan`, `WindowDeck.fanned` | Every tile visible at once, each peeking out from behind the one in front by a strip. |
| **deal** | сдача | `.deal`, `WindowDeck.dealt` | One tile, as in the flip, but the next one is simply there: no turn, no motion. |

In the configuration: `overlay_deck = "stack" | "fan" | "deal"`.

## Where each subject lives

| Subject | Where |
|---|---|
| the overlay | `Overlay/` — `OverlayWindowController`, `OverlayPanel`, `OverlayView`, `OverlayGrid`, `OverlayFitting` |
| Spaces | `Spaces/` — `SpaceQuery`, `SpaceTracker`, `DesktopSwitcher`, `MissionControl` |
| windows | `Windows/` — `WindowListService`, `WindowActivator`, `WindowCoordinator` |
| screenshots | `Thumbnails/` — `WindowThumbnailService`, `WindowPreviewCache` |

The `Window…` prefix on the services is deliberate: there it reads as part of a
phrase — an activator of windows — and confuses nothing. It is gone from the
entities, where a section is named after the Space it is, even when no window is
in it.
