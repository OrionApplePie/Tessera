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

Asked, now, and inferred when the asking fails.

There is no public way to ask. The window server knows, and answers
`SLSCopySpacesForWindows` — a SkyLight call with no header, no contract and no
promise to exist tomorrow. Measured against two fullscreen VS Code windows: the one
on screen answers with the active Space identifier, the other with a Space of its
own. No amount of watching can establish that second fact, because the two windows
are never on screen together and never on screen with anything else.

It is used, and it is isolated. `SpaceQuery` opens SkyLight by path and looks up
every function by name at run time, trying both the `SLS` and the older `CGS`
spelling. A symbol that has been renamed or removed is `nil`, `isAvailable` turns
false, and `SpaceTracker` — which infers Space membership from what appears on
screen together — answers instead. That fallback is what this project did before,
so an update that breaks SkyLight costs accuracy rather than function. It is also
switchable: `use_private_space_api = false`.

The highlight moves over both. A window and an empty Space are one list —
`OverlayTarget` — because a Space is a place you can go and the arrows have to
reach it; an empty one carries the highlight itself, having no tile to carry it.
It is never where the highlight starts, though: you are always in a window.

Raising a window and showing a Space are two different things, and the difference
matters. Raising asks Accessibility or a menu for a window, and the Space changes
only because that is where the window lives. Showing a Space touches no window at
all, which is the only way onto a desktop with nothing on it — the public way to
reach a Space is to activate a window that lives there, and an empty desktop has
none.

**A Space is shown by pressing the shortcut macOS binds to it, not by asking the
window server.** `SLSManagedDisplaySetCurrentSpace` looked like the answer and is
not: it writes the window server's "Current Space" field and stops there. Measured,
the field went from 5847 to 4556 while the external display went on showing the
same fullscreen window — so every check that read the field back agreed the switch
had happened, and a screenshot of the display proved it had not. On macOS 15 the
private call needs SIP disabled to do anything more than bookkeeping.

What works is the system's own "Switch to Desktop N": measured, ⌃3 posted from this
process took the external display from 5847 to 4556, and a screenshot of that
display showed bare wallpaper. Three things about it are worth knowing. The
numbering runs across displays and skips fullscreen Spaces, which macOS does not
number — on a machine whose built-in display holds desktops 1 and 2, the external
display's only desktop is 3. The shortcut is read from
`com.apple.symbolichotkeys` rather than assumed, because it is the user's to
rebind or switch off, and macOS binds no desktop past the eighth. And the event
goes to the HID tap: the window server reads its own shortcuts below every
application, so an event posted further up the chain reaches the front application
and never the shortcut. The arrow shortcuts ⌃← and ⌃→ ignore a synthesised event
entirely, with or without the function flag their preference entry carries.

**Who is in front when the keystroke goes out decides whether it holds.** With this
application in front, macOS answers a switch to an empty desktop by picking a front
application of its own — the one from the Space being left — and that application
brings its Space back: measured, the front moved 600 ms after the switch and the
display followed it 300 ms later. Handing the keyboard to that same application
first does fix the switch, and it was shipped that way for an afternoon, but it
leaves a fullscreen application in front of a desktop it owns no window on. Then any
activation at all — opening this overlay again — sends the display back to it, which
is what "the overlay opens on the previous desktop" turned out to be.

The keyboard therefore goes to Finder, which owns the desktop, and the display is
left in the state a person ends up in having switched desktops themselves. Finder is
activated without raising its windows: measured, that leaves every other display
where it is, while activating it the way AppleScript does raised a Finder window and
took the other display off its fullscreen Space with it. `NSApp.deactivate()` is no
help here — measured, it does not move this application out of the front at all.

Stepping through Spaces with the overlay still up hands nothing over, because
nothing took the keyboard away.

A desktop that is **already on screen** needs the opposite treatment. Its shortcut
does nothing at all — measured, pressing it changes neither the Space nor the focus
— yet choosing it from the overlay still means "take me there", and when it is on
another display that is a real move. macOS shifts its attention on a click or an
activation and never on the pointer alone: measured, moving the pointer to that
display left the active Space exactly where it was.

**The click lands on the menu bar, not on the desktop.** Clicking the wallpaper is
what "Click wallpaper to reveal desktop" listens for, and that setting is on by
default: measured, a click on an empty desktop slid every window on the other
display aside, and two Finder windows ended up parked at its bottom edge — which is
what "the windows slide down" was, and it was ours. The menu bar is the one part of
a display that is always there, belongs to no window, and answers a click by making
that display active — measured, the active Space moved across while every window
stayed where it was. The point is a third of the way in: past the application menus,
short of the status items, and clear of the notch in the middle of a built-in
display. The click is skipped while the overlay is up and being stepped through,
where it would land on the panel.

The overlay opens on the display showing the **active Space**, which is neither of
the two obvious answers. `NSScreen.main` is the screen of the window with keyboard
focus: measured, with the work happening in a fullscreen window on the external
display it still said the built-in one, and after showing a Space it names the
display just left — so the overlay opened on a Space nobody was looking at, and
which display that was depended on the application in front, which is why it looked
intermittent. The pointer is no better, and fails the other way: showing a Space
moves it to that display and it stays there after the attention has gone back to a
window elsewhere. `SLSGetActiveSpace` follows the focus across displays in both
cases — measured, activating an application on the built-in moved it there and back
again — and it is the same notion that decides where Spotlight opens.

Standing on a desktop with nothing on it, no tile is marked as the window you are
in, because there is none. The mark would otherwise sit on a Finder window on
another display every time, since Finder is what ends up in front.

The identifiers themselves are large and grow over time, so they are turned into
the small per-display numbers the overlay groups by, ordered by identifier — which
is the order the Spaces were made in, so a heading does not move about between
refreshes.


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

### A verdict only counts if nothing else was asked for

The store learns from what happens after an activation: a window still absent once
the switch has had time to happen did not come. Stepping breaks that reading, and
did — every press asks for the next window, so the one before is legitimately off
screen a second later, gets recorded as refusing to come, and disappears from the
switcher. Seen in the log as `Code came forward again; listing it once more`: it
had been hidden, and was only forgiven when it happened to come forward later.

So a pending verdict is dropped as soon as anything else is asked for. What is left
is the case the store was written for: one window asked for, nothing else asked,
and still nothing on screen.

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

## Reaching a particular window

Activating an application is easy and always works: `NSRunningApplication.activate()`
needs no permission, crosses Spaces, and macOS switches to the Space of whatever
window that application had in front. Reaching *one* window of several is the hard
part, and there is one rule behind every difficulty in it:

> **Accessibility lists only the windows on the Space that is active.**

Measured across seven applications. Word before activation reported no windows and
both documents two seconds after. Obsidian, brought forward, showed one of its two
— the other was on another Space. Chrome, Finder, Telegram, Todoist and Claude all
reported nothing while their windows were elsewhere.

That is why selecting one of three Chrome windows used to land on whichever the
application preferred: at the moment of choosing there was nothing to aim at.

Three ways to reach the window, tried in turn:

1. **Accessibility, immediately.** Works when the window is already on this Space.
2. **Accessibility again, after the switch.** Retried every 200 ms for two
   seconds, stopping the moment it works or the user goes elsewhere. This is what
   makes a second Word document reachable.
What none of them reaches: a particular window of an application with no scripting
dictionary that keeps that window on another Space. Obsidian is the example —
Electron, no `.sdef`, no `NSAppleScriptEnabled`.

`⌘\`` remains untried as a last resort. It cycles an application's windows with no
permission at all, but measured on Chrome it visited two of four windows, so it is
bounded by the active Space like everything else.

### The one-shot command needs the same fallback

`tessera focus <id>` used to activate the application, discard what the raise
answered, and print "Focused …" either way. Measured with two VS Code windows,
one of them on a desktop that was not showing: it printed
`Focused Code: … — Tessera` while the system focused `… — Fires`, the other
window — because Accessibility lists no window of a Space that is not showing, so
the application came forward and chose for itself.

It now falls through to the Window menu, as the overlay does, and says which way
the window was reached. A command that reports something it did not do is worse
than one that fails.

### The Window menu, for windows on another Space

Every fullscreen window is a Space of its own, and Accessibility lists only the
windows on the Space showing now. Two fullscreen windows of one application are
therefore invisible to each other: measured on VS Code, `kAXWindowsAttribute`
named the one on screen and nothing else, while the window server listed both.
Nothing else reaches them: Electron applications answer no scripting interface
either, which is what the third way used to be.

The application's own Window menu does list both, by title, across Spaces:

```
  "Проверка реорганизации п… — tec-ml-toolbox"
  "Cli example переименован… — Tessera"
```

Pressing that item raises the window and switches Spaces to it — verified by
watching which of the two VS Code windows the window server reported as on screen
before and after. It needs the Accessibility permission the switcher already asks
for and nothing further, which is why this is the last thing tried rather than a
permission to request.

It only acts on an application that is already frontmost. Pressing an item of one
that is not returns `noErr` and does nothing at all — measured twice, once by
accident: a switch reported that it had worked and left the window where it was.
Activation has only just been asked for when the menu would first be useful, so
usually the application is not frontmost yet, and the press waits for the system to
announce that it has arrived. That announcement is the same one the retries listen
for.

It is asked first, before the retries, because it answers the very case that leads
here — a window Accessibility cannot see — and answers it at once. Measured from
the tile being chosen to the window being up: 931ms when the menu came after three
retries and an Apple Event, 151ms when it is asked straight away, and 71ms for a
window of an application that had nothing else to do. What is left after that is
the system's own fullscreen transition, which is not ours to shorten.

Reading a menu is not free of consequence. An application whose menu bar is on
screen may actually put its menus up while they are read: measured on Word, a pass
over the whole bar left two menus standing open for 1.3 seconds — which is what
"Word's menu opens by itself" was. Reading one named menu two hundred times over
opened nothing at all, so only the Window menu is read, and it is closed with
`kAXCancelAction` afterwards in case it did appear.

Finding that one menu costs nothing: a top level menu's title can be read without
opening it. Failing a name match — the list of translations here is not
exhaustive — the last two menus are tried, because Window sits before Help at the
end of the bar in every application that has one.

Only items directly under a menu are considered, which is what keeps this away from
"Open Recent": its entries live one level deeper and would open a second window
rather than raise the one asked for. The menu is not identified by name — VS Code
has an English "Window" menu with Russian items, so no list of localized names
would hold — but by the item that matches the window's title.

### The two sources spell a window differently

A tile's title comes from the window server; the window is raised through
Accessibility, which does not always use the same string. Activity Monitor's
window is "Мониторинг системы" to one and "Мониторинг системы – Все процессы" to
the other, measured on macOS 26 with `kAXTitleAttribute` against `kCGWindowName`
for the same window id.

Matching on equality alone therefore aimed at nothing. The retry budget went by,
every way of asking was spent, and the log said the window could not be raised by
any means — while the application had come forward and its window was on
screen, because it had only the one. An application with several windows would
have raised whichever it liked.

`WindowTitleMatch` takes an exact match first, and failing that a candidate that
extends the title, or that the title extends — but only when exactly one does.
Two documents whose names begin alike are left alone: raising the wrong window is
worse than raising none, and "could not aim" is the truthful answer that also
teaches the learned-window store nothing.

## Windows the application does not own any more

A window can outlive what it showed. Finder reported one window through Apple
Events while the window server listed two; Chrome, Discord, Notion and Linear do
the same, which is [a known and unsolved problem in AeroSpace](https://github.com/nikitabobko/AeroSpace/discussions/1506)
— and that project reads the private APIs freely.

Everything public was checked and none of it separates a ghost from a real window:

| Signal | Ghost | Real |
|---|---|---|
| `kCGWindowMemoryUsage`, `StoreType`, `SharingState`, alpha | identical | identical |
| A thumbnail capture | succeeds, 74 ms | succeeds, 108 ms |
| Accessibility | absent | absent (Finder publishes neither) |

Two things do know. The private `CGSCopySpacesForWindows` reports no Space at all
for a ghost — exact, one call, and rejected here for the same reason as elsewhere.
And the application itself does not list it: not in a scripting interface, and not
in its Window menu, which is public, already read for raising, and the obvious
next step for filtering the list as well. That is not done yet.

Note that a minimized window also belongs to no Space, so neither signal can tell
a ghost from something in the Dock without asking Accessibility as well.

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

### Sharing a combination with macOS

Registering a combination macOS already owns succeeds. `RegisterEventHotKey`
returns `noErr`, both registrations stand, and the key goes to whichever of the
two asked for it last. Nothing reports the collision, and the symptom is not a
hotkey that never works — it is one that works for hours and then stops, with the
registration still live and nothing in the log. Restarting the app takes the
combination back, which makes it look like a bug in the app that a restart fixed.

The default shipped here, ctrl+alt+space, is also "Select the next source in the
Input menu" on any Mac with a second keyboard layout. It was measured on this one:
enabled, `parameters = (32, 49, 786432)` — space, key code 49, control plus option.

macOS publishes its own shortcuts in a preference domain rather than through an
API: `AppleSymbolicHotKeys` in `com.apple.symbolichotkeys`, one entry per
shortcut, each with an id, whether it is enabled, and three parameters — the
character, the virtual key code, and the modifiers as a Cocoa mask. HIToolbox
does export `CopySymbolicHotKeys`, but no SDK header declares it, so reaching it
means declaring the symbol yourself. Reading the plist needs no permission and no
undeclared symbol, so `SystemHotkeys` does that and `HotkeyController` warns,
naming the shortcut to switch off.

The ids worth knowing, all bound to the space bar: 60 previous input source
(⌃Space), 61 next input source (⌃⌥Space), 64 Spotlight (⌘Space), 65 Spotlight
file window (⌥⌘Space). The tab key carries no system shortcut at all.

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

## Settings

The configuration is read once at launch and handed to each service as values, so
the settings window saves by writing the file and asking for the app to be
replaced. The replacement is requested by a separate process — the one that posts
the quit notification, waits for the single-instance lock to be free, and starts a
fresh app — because doing that from inside the app that is quitting would mean
waiting for itself.

Writing regenerates the file rather than editing it: this is a subset parser with
no memory of layout, so hand-written comments and ordering are lost. The writer is
covered by round-trip tests — write a configuration, read it back, expect the same
configuration — which is the property that matters when a person's settings pass
through it.

## Reaching a window by its initial

A key press is a position on the keyboard plus whatever the active layout makes of
it, so the letter jump used to reach only names spelled in the layout in use.
Measured on ABC with a window called "Мониторинг системы" open: pressing the key
that carries "м" moved nothing, because that key reads as "v" there and no window
starts with it.

macOS will translate a key code through any installed layout — `TISCreateInputSourceList`
for the enabled sources, then `UCKeyTranslate` through each one's
`kTISPropertyUnicodeKeyLayoutData` — so a key can simply mean everything printed
on it at once. Key code 9 answers `["v", "м"]` on this machine.

That costs 16µs per press for two layouts, measured over a hundred calls, which is
why nothing is cached: a layout added while the app is running is picked up on the
next key press. Input methods that translate rather than map keys publish no key
layout and are skipped, as is any key that produces something other than a letter.

## Showing the overlay

The panel is placed by hand rather than by `center()`, on the screen `NSScreen.main`
names. That is the screen holding the window that has the keyboard, which is what
makes the overlay follow you between displays — measured by focusing a window on
the external monitor (`NSScreen.main` became VG27AQL1A) and then one on the
built-in (it became Built-in Retina Display).

Two things about showing it had to be measured, both invisible in code review and
obvious at four milliseconds of resolution. Poll `CGWindowListCopyWindowInfo` for
this app's own on-screen windows in a tight loop, press the hotkey, and print every
change in geometry; the flicker becomes a list of frames.

**Size and origin must be committed as one displayed frame.** Set separately and
left to be displayed whenever, they reached the window server *after* the
order-front did. The panel appeared at the size and position it had the previous
time — on the other screen, if that is where it last opened — and jumped to the new
one 27ms later:

```
0.580  858x1108@366,-1261   ← previous frame, still on the external monitor
0.607  1062x904@225,58      ← 27ms later, where it belongs
```

One `setFrame(_:display: true)` before `makeKeyAndOrderFront` removes it, in both
directions, every time.

**Whether the panel is up is a question for the window server.** `NSWindow.isVisible`
stays `true` for a panel that hid itself because the application was deactivated,
and it is also `true` for one that is on screen while the application was refused
activation — which is what happens over a fullscreen application. `NSApp.isActive`
does not separate those either: it is `false` in both. Believing the pair of them
meant the hotkey re-presented a panel that was already up rather than closing it,
and since presenting places the panel on the screen the frontmost window is on,
the panel slid from one display to the other in front of the person pressing the
key. That is the flicker that survived the fix above.

Listing what is on screen and looking for the panel's own window number answers it
without doubt. Describing that one window does not: `CGWindowListCreateDescriptionFromArray`
returns nothing at all for the asking application's own window, measured on
macOS 26. A panel that is somehow still on screen when it is about to be placed is
ordered out first, because moving a visible window is a move the eye follows.

**The hosting view must not size the window.** With its default sizing options an
`NSHostingView` pins the window's content size through constraints — reading
`contentMinSize` and `contentMaxSize` shows both set to the size the view wants.
Those constraints do not settle when the root view is replaced: they arrive after
the window is on screen, so the panel appeared at the size asked for and shrank
26pt a frame or two later. They cannot be read ahead of time either — at
presentation they still describe the *previous* layout, which is what makes them
useless as a prediction and dangerous as an input. `sizingOptions = []` leaves the
decision with the fitting pass, where it was meant to be.

That leaves the panel a little larger than the content wants, because the fitting
pass measures a view that is not in a window and lands about 26pt over what the
same view settles at inside one. The difference would show as a transparent band
along the edge, so the panel is painted at the layer as well as by the view in it,
in the same colour.

## Stepping through windows with the overlay open

The overlay is a map, and `⌃⌥⇧` with an arrow moves across it: the highlight moves,
the window under it comes forward, and the overlay stays up. It is the nearest
thing to a tiling window manager's directional movement that macOS allows, and the
map has to be the overlay because macOS arranges Spaces in no geometry a person
can navigate.

Three details make it work rather than merely happen.

The panel is a `.nonactivatingPanel`. It takes the keyboard without the
application becoming active — which over a fullscreen application it cannot do,
because macOS refuses that activation. Measured: with the panel key, seven steps in
a row all arrive; the arrows keep reaching the overlay rather than the application
behind it.

A step raises without activating where it can, so nothing comes forward and nothing
hides the overlay. Accessibility only reaches the Space showing now, though, and a
step onto any other one used to move the highlight and leave the window where it
was. So the full path is asked next — activation, then the Window menu — and that
one activation is marked as one the overlay survives.

One thing this cannot avoid, and it shows. Reaching a window on another Space
means activating its application, and macOS brings that application back to
whichever Space it was last on — not to the one being asked for. If those differ,
the display changes twice: once for the application, once for the window. With two
fullscreen VS Code windows that reads as Code disappearing and coming back oddly.
The menu press cannot come first, because a menu item of an application that is not
frontmost does nothing at all.

Which costs the keyboard: macOS gives it to whichever application is active, so
the panel goes quiet the moment a step brings another application forward, and the
mode died after one move. The arrows are therefore held system-wide, as Carbon
hotkeys, for exactly as long as the overlay is up — a Carbon hotkey arrives whoever
is frontmost. Measured: six steps in a row, every one with `key=false`, four of them
crossing displays. Released on hide, so `⌃⌥⇧` with an arrow means nothing to this
application the rest of the time — measured too.

Two things had to stop happening on every step for that to hold up. Accessibility
is asked with a messaging timeout, because an application busy with a Space
animation answers slowly and an unbounded wait on the main thread is the overlay
freezing. And the layout is measured once per screen rather than once per step: the
fitting pass builds the whole view twice over and then replaces the live one, which
is not something to do on a keypress. Measured after both: twelve steps in a row at
0-11ms each, eight crossings between displays at 4-9ms.

And when a step lands on another display the panel travels there, over
`followDuration`, rather than teleporting or staying behind. Measured across the
pair here: fifteen frames from the external display to the built-in in about 170ms.
Long enough to be followed by eye, short enough that a held arrow does not leave
the panel several steps behind.


`⌃⇧` with an arrow moves the highlight and brings that window forward without
closing the overlay. It raises the window through Accessibility and does not
activate its application, which means it only reaches windows on the current
Space — Accessibility lists no others.

That limit is the residue of three attempts, each measured:

| Approach | Result |
|---|---|
| Activate the application, reclaim focus at once | 1 step of 4; a miss in Accessibility raised the desktop instead |
| Raise the window, never activate | 6 steps of 6, current Space only |
| Activate, reclaim focus after 350 ms | 2 steps of 5 |

The first and third fail for one reason: `NSApp.activate` is a request. An
application that is not in front cannot simply take activation back, and the
system is free to refuse — so after a step or two the overlay stops receiving keys
and looks frozen. Waiting longer does not help, because the problem is not timing.

The way out is not to need focus at all, and that is what is done now. A Carbon hot
key is delivered to this process whatever is in front — that is how the global
hotkey works from inside Safari. `⌃⌥⇧` with the arrows is registered the same way
for as long as the overlay is up, so a step can activate an application, cross a
Space, and still have the next press arrive here. Measured: six steps in a row, all
with the panel not key.

The panel is not a non-activating one, though that sounds like exactly what a
switcher wants. Non-activating means the application never becomes active, and
macOS routes ordinary key events to whichever application is — so the panel was
key inside a process nobody was typing at, and the arrows and Return went to the
window standing behind the overlay. It was added to fix keys over a fullscreen
application and quietly broke them everywhere else. What covers the fullscreen case
is the handful of keys held as Carbon hotkeys while the overlay is up, which arrive
whoever is frontmost.

The keyboard is also taken straight back. Reaching a window on another Space means
activating its application, and macOS hands the keyboard to whichever application
is active — but a non-activating panel can be made key without its own application
becoming active, so the overlay asks for it back the moment it hears that
activation. Measured across five steps: key=true after every one, while Code,
Claude, Finder and Spotify took turns being frontmost. That is the arrangement the
mode wants — you type at the overlay and look at the window it just raised.

Escape, Return, the keypad's Return and Space are held with them anyway, as the
floor under that. The keyboard comes back a moment *after* the step, and a key
pressed inside that moment would otherwise land in the application that came
forward — which is how Escape, then Return and Space, were reported as doing
nothing at all. Escape did nothing, and neither did the keys
that mean "this one" — which is how both were reported. Pressing a confirm key
finishes the switch and closes the overlay whatever `close_after_activation` says,
because that setting is about picking a tile with a mouse or a number, and a confirm
key is someone saying they are done looking.

What it costs is honest to state: those eight keys stop reaching other applications
while the overlay is up, and Space and Return are not small keys to borrow. They
are released the moment it closes — verified by pressing each afterwards and
watching nothing happen at all.

## Who decides the overlay is on screen

The panel used to hide itself: `hidesOnDeactivate`, the default for an `NSPanel`.
That is two behaviours in one flag, and both of them bit.

AppKit remembers a panel it hid that way and puts it back the moment the
application is activated again — so opening the settings window from the menu bar
brought the switcher back on screen beside it, unasked. Ordering the panel out
first does not help: it is already out, and that is not what the list is keyed on.

And the flag only fires if the application was active to begin with. Refused
activation over a fullscreen window, the application never becomes active, is
therefore never deactivated, and the panel stays up with nothing to take it down.

So the flag is off and the decision is one place: the overlay hides when another
application comes forward. Which application that is comes from the notification
itself — asked of the workspace afterwards, the answer was sometimes still the
application that had just left, and the overlay hid itself the instant it was
shown.

Any application, including the one the overlay has just raised a window in.
Excepting that one sounded right, since `close_after_activation = false` says the
overlay stays up while windows are picked from it, but it is not what the panel did
before: AppKit hid it whenever this application was deactivated, whoever had taken
over. Excepted, picking a window left the overlay on screen, which reads as an
overlay that will not go away. Stepping through windows still keeps it, because a
step raises a window without activating its application, so nothing comes
forward — which is the whole reason that mode exists.

## What opening the map costs

Measured on this machine, from the keystroke to the panel being on screen, with a
watcher outside the process reading Tessera's own Accessibility tree:

| | before | after |
|---|---|---|
| open, warm | 132-206 ms | 40-65 ms |

Three things were paying for it, and the log said which:

- **Waiting for the window list.** `SCShareableContent.current` takes 67-115 ms
  here, with 350 windows on the machine, and the map used to wait for it before
  drawing anything. It now draws on the list already in hand and lets the fresh one
  arrive behind it — the list is rebuilt every few seconds anyway, so it almost
  always answers with the same thing. The highlight is put back where opening would
  have put it once the fresh list lands, but only if nobody has moved it since.
  Only the very first open, with nothing to draw at all, still waits.
- **Measuring the layout again for a map that had not changed shape.** The fitted
  size is cached against what the map is made of, and that signature used to
  include how many windows each Space holds — so a window opening anywhere cost
  123 ms and fourteen trial layouts on the next open. It does not: a deck is drawn
  at one tile's size whatever it holds (`deckDepth` is a constant), and the only
  thing a count moves is the badge beside the heading, which is why the signature
  keeps the count's *shape* — none, one, a badge of one digit, a badge of two.
- **Two refreshes at once.** Closing the overlay asks for a fresh list while the
  timer's own is still in flight: two enumerations and two capture passes for one
  answer. A refresh now folds into the one already running, and only runs after it
  if it wanted thumbnails that one was not taking.

What is *not* worth chasing: nothing happens while the map is up. The list is held
and the captures stop, so the map does not move under the hand — measured over six
seconds of an open overlay, the log is silent.

## The numbers, and which of them are settings

There were seven of them, and most were guesses at how long something else would
take. Two remain, because most of the questions had an answer better than a number.

**Ask when told, not on a timer.** macOS announces a Space change and an
application coming forward, and both are exactly the moment an unreachable window
may have become reachable. Waiting for the announcement replaced ten attempts two
hundred milliseconds apart — but only in a real application: measured, a plain
command-line process listening for `NSWorkspace.activeSpaceDidChangeNotification`
never hears it, while the same code as an accessory application hears every switch
about half a second after the key, which is the animation. Tessera is an accessory
application, so it hears.

**Wait for the condition, not for a duration.** A capture hangs because the window
has no surface — it is minimized, or its application has stopped drawing. That
state does not end after five minutes, it ends when the window is on screen again,
and the window server says so on every refresh. A cooldown was a guess in both
directions; the edge is exact.

**Delete the mechanism, delete its timing.** The Apple Events path had its own
timeout, its own setting and its own permission prompt for every application. The
Window menu reaches the same windows — Finder, Chrome and friends, verified — and
also the ones Apple Events never could, so the whole path went, and the number with
it.

What is left is `activation_settle_seconds`, the point at which waiting for the
system stops, and `unresponsive_after_seconds`, the point at which not answering
becomes wedged rather than busy. Neither can be derived from an event: a capture
that never returns and one that is slow look the same until time passes.

Three numbers stay in the code and out of the config: how long `quit` and `restart`
wait for the lock to be released, how often they look, and how far the run loop is
pumped between those looks. They are not waiting on another application's
behaviour, they are the mechanics of one command waiting for one process it has
just signalled.

## Moving a window somewhere else

A window belongs to the display that covers most of it — that is the whole rule —
so sending one to another screen is putting its rectangle there and nothing more.
`WindowActivator.send(_:toDisplay:)` reads the frame through Accessibility, asks
`DisplayInfo.frame(_:movedFrom:to:)` where it goes, writes it back, and then reads
it again: `kAXPosition` and `kAXSize` are requests, and an application may clamp a
size, hold a minimum, or refuse outright. The position is written twice because a
resize can push a window back onto the screen it came from.

The place is kept in proportion to the room the window has to move in rather than
in points, so a window against an edge arrives against that edge whatever the two
screens measure, and only a window too large for its new screen is scaled — sent
across and back, it should be the size it left with.

Two things fall out of that. With displays keeping separate Spaces, a window sent
to another display lands on whatever Space that display is showing, which is as
close to moving between Spaces as anything here gets. And a window Accessibility
will not list cannot be moved at all: Finder's windows never appear, and neither
does a window on a Space that is not showing, so the answer there is to say so.

### Between Spaces of one display, nothing works

There is no public interface, and on macOS 15 the private ones are closed too.
Measured on 15.7.5 with SIP enabled, against a real window, reading the window
server back after each attempt:

- `SLSMoveWindowsToManagedSpace` — the call returns, the window does not move.
  Tried from Tessera itself, with Accessibility and Screen Recording granted, so
  it is not a permissions problem.
- `SLSSpaceSetCompatID` + `SLSSetWindowListWorkspace`, which is what Hammerspoon
  used through macOS 14 — `SLSSetWindowListWorkspace` answers 1006,
  `kCGErrorNotImplemented`.
- `SLSPerformAsynchronousBridgedWindowManagementOperation`, the newer path that
  works on macOS 26 with SIP enabled — the symbol is not exported here at all. The
  class it operates on, `SLSBridgedMoveWindowsToManagedSpaceOperation`, already
  exists in this version, with `performWithWMBridgeDelegate` and `invokeFallback`
  on it: the mechanism is in place, the way in is not.

What is left is yabai's route — injecting a scripting addition into Dock, which
owns the window server connection that may do this — and that needs SIP partially
disabled. Hammerspoon has carried the same breakage since macOS 15.0 as an open
issue. This is a hole between two mechanisms rather than a permanent state: the
bridged operation is how it works on the next major version.

### Except by hand, where it half works

Every *call* is shut. The gesture is not: in Mission Control a window moves to
another Space when its thumbnail is dragged onto that Space in the bar, and a
drag is a press, a path and a release, which anyone may make.

Measured, with SIP enabled and no private call: a TextEdit window dragged from
its thumbnail onto "Desktop 2" went there, and `SLSCopySpacesForWindows` — asked
before and after, which is what answers here, because a thumbnail leaving the
screen only says Mission Control redrew — reported the new Space. Dragged onto
the *other display's* bar it changed display and Space at once. The same drag,
driven from `tessera move`, moved a window and the switcher then listed it as
off-screen, which is what a window on another Space looks like.

And then it was taken out. Driven from the map — choose a destination with the
keys held, send on release — it failed more often than it worked: `Could not
send Finder to that Space`, with the destination correct in the log and the
window still where it started. Why the same drag lands from one caller and not
from the other was not chased down. What is recorded here is that the door is
not locked, not that the way through it is known.

Three things any second attempt will meet:

- The pointer really moves. There is no way to make the gesture without making
  it, and it has to be put back afterwards.
- A single leap does not work. The window server reads movement, not endpoints:
  a press and a release at two points move nothing, and neither does one jump
  between them, so the path has to be walked in steps.
- Mission Control draws only the windows of the Space its display is showing. A
  window anywhere else has to be brought forward first, which is visible.

## Telling a player to play

A media key is a system-defined event, and macOS gives it to whatever it already
considers the application that is playing. That is right for pausing what you can
hear and useless for starting something silent, so a scriptable player — Spotify,
Music, TV, VLC — is addressed with an Apple event instead, which reaches the
application it names and no other.

Except that it does not, here. Measured: `Not authorized to send Apple events to
Spotify`, with no dialog shown and nothing to allow afterwards. Automation
permission is granted to a *bundle*, and this is a plain executable with no bundle
identifier for the system to attribute the request to — the same reason the Screen
Recording prompt names the terminal rather than Tessera. So the addressed command
is attempted, and when it is refused the media key is sent anyway: measured, that
starts Spotify from silence, because macOS remembers which player was last.

Returning after the refusal — which is what the first version did — left the key
doing nothing at all, which is how this was found.

## Saying it in another language

Three separate things send a package's strings somewhere they are not, and all three
fail the same way — by handing back the key. The keys here are English sentences, so
a broken lookup reads as a program that simply has no translation. Each of these was
measured failing before it was fixed.

- **`Bundle.main` is not where they live.** A plain executable has no bundle of its
  own to hold resources, and both SwiftUI's `Text("…")` and a bare
  `String(localized:)` look there.
- **`Resources` is not where they are either.** SwiftPM puts the `.lproj` folders at
  the root of its resource bundle and leaves an empty `Resources` folder beside them.
  Foundation sees that folder, concludes the bundle keeps its resources inside it,
  and looks for the tables in the empty copies. Measured:
  `Bundle.module.localizedString(forKey: "Cancel")` answered `Cancel` while `Отмена`
  sat in `ru.lproj/Localizable.strings` two directories away. Naming the language
  folder as the bundle fixes the lookup — and then `String(localized:bundle:)` fails
  in its own way, because it looks for a `.lproj` folder *inside* the bundle it is
  given. `localizedString(forKey:value:table:)` is what answers.
- **The system's own choice of language is not the system's.** Measured, in a process
  whose `Locale.preferredLanguages` was `["ru-RU", "en-RU"]`, offered a bundle
  carrying both: `Bundle.preferredLocalizations(from:)` answered `["en"]`. A process
  with no bundle of its own has no language of its own as far as that call is
  concerned, so the match — region ignored, the person's order kept — is made in
  `language(preferring:among:)`.

Installed, the bundle has to travel with the binary: Homebrew puts both in `libexec`
and links the command into `bin`, because `Bundle.module` looks beside the executable
and *crashes* when it finds nothing. Measured through that layout: `using=ru.lproj`.

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
- Expecting `NSApp.activate` to bring an application that is not in front back to
  the keyboard.
- Expecting Accessibility to list a window that is on another Space, whichever
  application owns it.
- Looking for a public field that marks a window its application has forgotten.
- Expecting an Apple event to be permitted from a binary that is not an app
  bundle: it is refused, and refused silently.
- Moving a window between Spaces on macOS 15 by any private call: neither
  `SLSMoveWindowsToManagedSpace` nor the `SLSSpaceSetCompatID` workaround does
  anything, whatever permissions the caller holds. Only the drag in Mission
  Control does, and only sometimes — see above before spending a day on it.
- Dragging a thumbnail in one jump, or with the press and the release alone: the
  window server reads movement, not endpoints.
- Finding Mission Control's buttons by their labels, which are localised, or by
  their shape alone, which the row of window thumbnails shares; or expecting the
  Spaces to sit in an `AXGroup` — they sit in an `AXList`.
- Reading a button's action list the instant Mission Control opens and believing
  what it says about what that button can do.
- Opening Mission Control without checking whether it is already open.
- Reading a failure to open Mission Control as a bug before checking whether the
  screen was locked.
- Trusting `String(localized:)`, `Text("…")` or `Bundle.preferredLocalizations` in a
  package that ships its own strings: each of the three answers plausibly and
  wrongly.
