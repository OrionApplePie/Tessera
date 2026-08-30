# Mechanisms

Why the non-obvious parts of Tessera are built the way they are, what was
measured, and what was tried and rejected. `README.md` says what the app does;
this says why it could not be done more simply.

Every measurement here was taken on a two-display Apple Silicon Mac, macOS 26,
with Screen Recording and Accessibility granted.

## Enumerating windows

`SCShareableContent.current` is the source of truth, not `CGWindowListCopyWindowInfo`,
because ScreenCaptureKit is also what captures the thumbnails. Enumerating and
capturing through one framework means a tile and its preview share a `CGWindowID`
exactly, with no fuzzy matching. An earlier version of this project matched
AeroSpace's window list against screenshots by scoring names and titles — about a
hundred lines of heuristic that this removes entirely.

The filter keeps layer-0 windows with a non-empty title, at least 40pt on each
side, owned by another process. What it deliberately does **not** require is
`isOnScreen`: a window on another Space is exactly what a switcher is for.

`isOnScreen` means "on the active Space of its display, not minimized, not
hidden". It says nothing about occlusion — a window buried under three others is
still on screen.

## Which display a window is on

Frames come from `SCShareableContent.displays`, never from `NSScreen`.

Both describe the same monitors, but AppKit puts the origin at the bottom left
and ScreenCaptureKit at the top left. Pairing an `NSScreen.frame` with an
`SCWindow.frame` therefore needs every rectangle flipped, and the mistake hides
well: on a single display everything is at positive coordinates and looks right.
The development machine has an external monitor standing above the built-in one,
which puts it at `y = -1440`, and that is where such a bug surfaces.

A window belongs to the display covering the largest part of it — the rule macOS
itself uses for a window straddling two screens. Touching an edge is not
covering: a zero-area intersection does not count.

Only `NSScreen` knows the human-readable name, so the two are paired by display
id through `deviceDescription[NSScreenNumber]`.

Sections are ordered by geometry, not by which display is main or focused, so
they do not reshuffle between refreshes. Displays are banded into rows first,
because two monitors side by side are almost never aligned to the pixel and a few
points of offset should not decide which is "higher"; screens sharing at least
half the shorter one's height count as one row.

## Which Space a window is on

**macOS publishes no API for this.** `NSWorkspace` will say that the active Space
changed, never which one it is. `SCWindow` only reports whether a window is on
screen right now.

The private SkyLight framework does know. Measured directly, `CGSCopySpacesForWindows`
returns an exact Space id per window and `CGSCopyManagedDisplaySpaces` returns the
ordered Space list per display, including which are fullscreen:

```
built-in: spaces=[3, 3310, 3745, 3759] types=[0,4,4,4] current=3
external: spaces=[3573, 3754]          types=[4,0]     current=3754
Claude → built-in space 2/4     Arc → external space 1/2
```

It also answers a question nothing else does: a minimized window belongs to no
Space at all. That is what yabai and AeroSpace use, and it was **rejected here**:
the symbols carry no compatibility promise, and this project's claim to use only
public frameworks is worth more than exact Space numbers.

What is used instead is observation. Every window on screen at one moment shares
one Space per display, so each refresh is a membership set for whichever Space is
active. `NSWorkspace.activeSpaceDidChangeNotification` says when to look again.
Repeated sets build a partition; the set sharing the most windows with what is on
screen is the Space being looked at, and a window seen there is removed from every
other Space, because a window is on exactly one.

The limits are inherent rather than unfinished:

- Spaces are numbered in the order they were first visited, which need not match
  Mission Control's order.
- A Space never visited while Tessera was running is unknown, and its windows are
  listed as `Other Spaces` rather than guessed at.
- A minimized window is on no Space here either — it is never on screen.
- What was learned is forgotten on restart. Spaces are volatile enough that
  keeping stale knowledge would be worse than rebuilding it.

## Thumbnails, and the capture that never returns

`SCScreenshotManager.captureImage` can hang forever. A minimized window has no
surface, and the call neither returns an image nor an error. Measured across
thirteen windows: twelve answered in 74–124 ms, one minimized window never
answered at all.

That single window used to stall the whole refresh loop. `refreshNow()` awaited
it, `startRefreshLoop()` was never reached, and the app quietly stopped updating
while still showing tiles. The bug predated Spaces support; listing windows from
other Spaces merely made it certain to happen.

Each capture therefore runs under a two-second timeout, and a timed-out capture is
**abandoned rather than awaited**. This is the one place unstructured `Task` is
correct: a `TaskGroup` waits for every child before returning, so racing a capture
against a timeout inside one reproduces the hang exactly. The abandoned task leaks
its continuation, which is why a window that times out is remembered and not asked
again for five minutes — the leak is bounded by the number of wedged windows
rather than repeated every refresh.

Capture sizes count pixels; the target size in the config counts points; a Retina
display draws two pixels per point. Capturing at the point size produced an image
at half the density the tile is drawn at, and the view stretched it — the reason
thumbnails looked soft. The capture is scaled by the densest attached screen's
`backingScaleFactor`, and never above the window's own size, since upscaling adds
bytes and no detail. Thirteen windows at 2x cost about 900 ms per refresh against
roughly 800 ms at 1x: the per-call overhead dominates, not the pixels.

A minimized window is not asked at all, once Accessibility has said it is
minimized. It keeps whatever preview was captured before it went to the Dock; one
minimized before Tessera started shows its application icon instead.

## Minimized windows

ScreenCaptureKit cannot tell a minimized window from one on another Space — both
are simply not on screen — and the difference decides whether a capture will hang
and whether activation needs to restore the window first.

Accessibility is the only public API that knows, through `kAXMinimizedAttribute`.
Two things about it were learned the hard way:

- **The messaging timeout must be generous.** At 250 ms it worked for one
  application and silently reported "nothing is minimized" for the rest. At 500 ms
  Safari, Arc and Telegram still did not answer. At 2 s every application answered.
  A timeout that is too tight does not fail — it lies.
- **Even a generous timeout is not a guarantee.** A later measurement, in a
  trusted process at 3 s, had six applications of eleven return an empty window
  list — the same applications that had answered fifteen minutes earlier. The
  cause was not established. Treat an empty Accessibility window list as "unknown"
  rather than "no minimized windows", which is what the degraded path already does.
- **Only ask about applications that need it.** Applications with a window off
  screen are asked; the rest cannot have a minimized window worth knowing about.
  A refresh with this in place measures 87 ms.

Raising a minimized window does nothing, so `WindowActivator` clears
`kAXMinimizedAttribute` before `kAXRaiseAction`.

Without the Accessibility permission this degrades: nothing is reported as
minimized, a capture is attempted, and the two-second timeout catches it.

## Leftover windows of tray applications

A tray application often keeps its window object alive after you close the window.
It stays in the window server: layer 0, a title, not on screen — indistinguishable
from a window on another Space. Every public signal was checked:

| Signal | Result |
|---|---|
| `SCWindow.isActive` | Exactly duplicates `isOnScreen` on all thirteen windows |
| `NSRunningApplication.activationPolicy` | `regular` for the tray app, `accessory` for an app with a real window — backwards |
| Accessibility window list | Lists the closed window alongside real ones |
| `CGSCopySpacesForWindows` (private) | Distinguishes it — the window is on no Space |

So nothing about the window says it is a leftover. What does say so is the outcome
of asking it to come forward: a real window arrives, a leftover does not. A window
activated and still absent 1.5 s later, while still existing, is left out from then
on.

The delay is not padding. A Space switch runs an animation, and a verdict passed
immediately would condemn a real window for being slow.

This costs one wasted switch per such window, once. There is no way to know
beforehand, and probing windows unprompted would throw the desktop around.

The verdict is written to `~/.config/tessera/learned-windows.txt` — one window per
line as application, tab, title — because it is a property of the application
rather than of the session. It is the only thing Tessera writes apart from its
lock file, and it is meant to be edited. The lesson is dropped automatically the
moment such a window appears on screen, which is what happens when you open it
from the tray again.

Two limits: only the overlay teaches, because `tessera focus` runs in a process
that exits before the verdict is due; and a window is recognised by application
and title, so a Finder window reopened on the same folder starts out hidden until
it is seen on screen once.

## Fullscreen windows

Whether a window is fullscreen cannot be told reliably in public API either.

Geometry does not work. On a display with a notch, a fullscreen window avoids the
menu bar area by default, so it is the same shape as a maximised ordinary window:
measured on the built-in display, a normal Safari window was `[0,38 1512x944]` and
a fullscreen Claude window `[0,37 1512x945]` — one point apart.

The undocumented `AXFullScreen` attribute is correct when it can be read: it
agreed with the private ground truth on both windows where the Accessibility
window list was available. It inherits that list's unreliability, so it answers
for some applications and not others.

The private API knows exactly — a Space of `type == 4` is a fullscreen Space —
and is not used here for the same reason as elsewhere.

What is free: a fullscreen Space holds exactly one window, so a learned Space with
a single member is probably fullscreen. Measured against the ground truth on a
normal desktop, three fullscreen Spaces held one window each and the ordinary
Space held six. It cannot tell that from an ordinary Space you happen to keep one
window on.

## The global hotkey

Carbon's `RegisterEventHotKey`, not an `NSEvent` global monitor. It needs no
Accessibility permission and it consumes the key press instead of letting it
through to the focused application, which a monitor cannot do.

Its C callback decodes the event before hopping to the main actor. `EventRef` and
the context pointer are not `Sendable`; a main-actor `HotkeyController` is, being
globally isolated, so only the controller reference crosses the boundary. Doing it
the other way round requires `nonisolated(unsafe)` to silence a real diagnostic.

Carbon dispatches hot key events on the main run loop, which is what makes
`MainActor.assumeIsolated` in that callback sound rather than hopeful.

## Activation

Two steps, and neither is sufficient alone: `NSRunningApplication.activate()`
brings the owning application forward, and `AXUIElementPerformAction(kAXRaiseAction)`
picks the right window out of that application's several. Without Accessibility
only the first happens, and `WindowActivator` throws rather than pretending it
worked.

Windows are matched to Accessibility elements by title. It is the same fragile
handle the minimized check uses, and the reason both are documented as
best-effort: two windows with one title cannot be told apart this way.

**Accessibility does not list every window.** Measured on Finder: its own model,
asked through AppleScript, reports two browser windows; the window server reports
three titled layer-0 windows, two of them sharing a title; and Accessibility
reports exactly one window — the desktop, 2560x2422, untitled. Finder's browser
windows are absent from it entirely, three attempts in a row.

A raise therefore cannot always aim at the window it was given, and falls back to
whatever Accessibility does offer. `WindowActivator` reports which of the two
happened, because the difference decides whether the outcome means anything:

> The learner condemned a real Finder window before this distinction existed. The
> window did not come forward because nothing had asked it to — the raise had hit
> the desktop instead — and a verdict was passed on it anyway. An activation that
> could not aim proves nothing, and now passes no verdict.

The practical consequence is worth stating plainly: a Finder window on another
Space cannot be brought forward by this route. The application comes forward, its
frontmost window decides which Space you land on, and the window you asked for is
not reachable through any public API.

## What a reader should not try again

- Pairing `NSScreen` frames with ScreenCaptureKit frames without flipping Y.
- Racing a capture against a timeout inside a `TaskGroup`.
- Trusting a sub-second Accessibility messaging timeout.
- Looking for a public flag that marks a tray application's leftover window.
- Telling a fullscreen window from a maximised one by its frame.
- Capturing thumbnails at point sizes and expecting them to look sharp.
- Treating an Accessibility window list as an inventory of an application's
  windows, or a failed activation as proof about the window rather than about the
  attempt.
- Reading Space membership from anything public.
