# AGENTS.md

Guidance for AI coding agents working in this repository.
Human contributors: see `README.md` and `CONTRIBUTING.md`.

## Project

- **Name:** Tessera
- **What it is:** A native macOS window switcher. It runs as a background menu bar
  utility, keeps per-window thumbnails in RAM, and shows a centered overlay for
  switching between open windows. It also exposes a small CLI for automation and
  debugging. It depends on no external tool: windows are discovered through
  ScreenCaptureKit and focused through `NSRunningApplication` plus the
  Accessibility API.
- **Package manager:** Swift Package Manager
- **Minimum target:** macOS 13.0; window thumbnails need macOS 14.0 and degrade
  to name-only tiles below it
- **Swift version:** 6.2 toolchain, Swift 6 language mode pinned in `Package.swift`
- **UI:** SwiftUI overlay hosted in an AppKit `NSPanel`; AppKit menu bar item

Tessera ships as a bare SPM executable, not an `.app` bundle. That is deliberate
for now, and it has one consequence worth knowing: TCC prompts are attributed to
the launching terminal rather than to Tessera.

## Commands

Always use these. Do not invent alternative invocations.

```bash
make build          # swift build (debug)
make test           # run the full test suite
make test-one       # FILTER='SomeTests/testName' make test-one
make lint           # SwiftLint, strict
make format         # swift-format / SwiftFormat, in place
make check          # format --lint + lint + build + test — run before declaring work done
make run            # run the app/CLI locally
make clean
```

Raw `xcodebuild` output is unreadable; if you must call it directly, pipe through
`xcbeautify`. Read test failures from `.build/` logs or
`xcrun xcresulttool get --format json --path <path>.xcresult`, not from scrollback.

## Definition of done

A change is not finished until `make check` passes with zero warnings.
Warnings are errors here — do not leave them for a human to clean up.

Without full Xcode installed, `make test` and `make lint` need help finding the
toolchain, and the Makefile supplies it: Command Line Tools keep
`Testing.framework` and `sourcekitdInProc` outside the default search paths, and
they do not ship the `_Testing_Foundation` cross-import overlay at all, so
`import Testing` next to `import Foundation` only builds with overlay lookup
disabled. `make check` handles this on its own; the flags stay empty under Xcode.
The one warning it cannot suppress there is `ld` noting that CLT's
`Testing.framework` was built for macOS 14 while the package targets 13. It comes
from the toolchain, not from this code, and does not appear in CI.

## Layout

```
docs/mechanisms.md       why the non-obvious parts work as they do — read before
                         changing window enumeration, Spaces, thumbnails or
                         activation, it records what was already tried
docs/packaging.md        how it is installed and what a release needs
Formula/tessera.rb       the Homebrew formula; the tap is a repository of its own
Sources/Tessera/         the executable: one line calling the library
Sources/TesseraKit/      everything else, in folders by what it is about:
                         App, CommandLine, Config, Windows, Spaces, Thumbnails,
                         Overlay, Search, Hotkeys, Settings, Support
Tests/TesseraKitTests/   tests, in the same folders as the code they cover
Package.swift            single source of truth for targets and deps
```

Mirror the source tree in tests, folder for folder:
`Sources/TesseraKit/Windows/WindowListService.swift`
→ `Tests/TesseraKitTests/Windows/WindowListServiceTests.swift`.

`TesseraApp.main()` is the only `public` thing in the library, because the
executable is the only thing outside it. Everything else stays `internal`, which
`@testable import TesseraKit` reaches — adding `public` to make a test compile is
the wrong fix.

Not every source file has a test yet. `WindowCoordinator`, `WindowListService`,
`WindowThumbnailService` and `WindowActivator` take their collaborators as
concrete types, so covering them means introducing protocols first — do not do
that as a drive-by; it needs its own change.

## Code style

- Follow the Swift API Design Guidelines. Formatting is enforced by the
  formatter — never hand-tune whitespace, run `make format`.
- No force unwraps (`!`), no `try!`, no force casts in production code.
  They are acceptable inside tests where a failure should abort the test.
- Prefer `struct` and `enum` over `class`. Use `final class` when reference
  semantics are genuinely needed.
- Errors: typed `enum` conforming to `Error`, thrown with `throws`.
  Never swallow an error into a silent `nil`.
- Access control is explicit. Default to `internal`, use `public` only for
  the package's real API surface.
- No new third-party dependencies without asking first. Prefer the standard
  library and Apple frameworks.

## Concurrency

Strict concurrency checking is on. This is the area agents most often get wrong.

- Actor-isolate mutable state. UI types are `@MainActor`.
- Do not add `@unchecked Sendable` or `nonisolated(unsafe)` to silence a
  compiler diagnostic. If a data race warning appears, fix the ownership model
  or stop and ask.
- No `DispatchQueue` in new code; use structured concurrency.
- No unstructured `Task { }` where a child task in a `TaskGroup` or `async let`
  would do. Every task must have a defined lifetime and cancellation path.

## Testing

- Framework: swift-testing (`import Testing`, `@Test`, `#expect`).
  Legacy XCTest files exist; do not migrate them opportunistically.
- Hoist `try` out of `#expect`: the macro expansion does not propagate a thrown
  error, so `#expect(try lock.tryAcquire() == true)` does not compile. Bind the
  call to a `let` first, then assert on the value.
- Every bug fix starts with a failing test that reproduces the bug.
- Tests must be deterministic: no real network, no `sleep`, no dependency on
  wall-clock time or on machine locale. Inject clocks and URL protocols.
- Do not weaken or delete an assertion to make a test pass. If a test is wrong,
  say so and explain why before changing it.

## macOS specifics

- Logging via `os.Logger` with a per-subsystem category. No `print` in
  production code.
- App Sandbox is NOT enabled and there are no entitlements: this is a plain SPM
  executable, not a bundle. Do not add `*.entitlements` without agreeing on the
  packaging change first.
- A tray application's closed window is indistinguishable from a window on
  another Space by any public means: `SCWindow.isActive` only repeats
  `isOnScreen`, the activation policy is `regular` for both, and Accessibility
  lists the closed window too. Only the outcome of an activation separates them,
  which is what `ActivationVerifier` and `LearnedWindowStore` are for.
- Space membership is learned, not queried: macOS exposes it only through the
  private SkyLight framework, which this project deliberately does not touch.
  `SpaceTracker` infers it from the fact that windows on screen together share a
  Space. Treat its answers as best-known rather than authoritative — an unvisited
  Space is genuinely unknown, and saying so is the point.
- `SCScreenshotManager.captureImage` can hang forever: a minimized window has no
  surface, and the call neither returns an image nor an error. Every capture therefore runs under a timeout, and a timed-out capture
  is abandoned rather than awaited. This is the one place unstructured `Task` is
  correct: a `TaskGroup` awaits every child before it returns, so a single wedged
  window would stall the whole refresh loop. It did, before the timeout existed.
- Two TCC permissions gate the whole product, and each has a defined degraded
  mode. Screen Recording: without it the window list is empty. Accessibility:
  without it activation raises the owning application but not a specific window.
  Never fail silently on a missing permission — surface it, the way
  `WindowActivator` and `tessera permissions` already do.
- User-visible strings go through `localized(…)` — never `String(localized:)`,
  never a bare SwiftUI `Text("…")`. Three separate things send a package's strings
  to the wrong place, and all three fail by showing the key, which is English and
  therefore looks like a translation that was not needed; `Support/Localized.swift`
  records what each of them was. Anything with a number or a name in it is a format
  (`"Desktop %lld"`), because that is what the tables hold. After adding a string,
  run `make strings`: it regenerates the tables from the code and lists what has no
  Russian yet. The CLI's own output and every log line stay English.
- The global hotkey is Carbon (`RegisterEventHotKey`): it needs no permission and
  it consumes the key press, which an `NSEvent` global monitor cannot do. Its C
  callback decodes the event before hopping to the main actor — `EventRef` and the
  context pointer are not `Sendable`, while the main-actor `HotkeyController` is,
  so only the controller reference crosses. Do not "fix" that hop with
  `nonisolated(unsafe)`.
- Spaces can be created and closed, but only through Mission Control's own
  buttons in the Dock's Accessibility tree (`MissionControl`,
  `MissionControlTree`). The SkyLight calls for it are exported and privileged.
  Match those buttons by the shape of the tree and never by their labels, which
  are localised; a press is not an outcome, so count the Spaces before and after;
  opening Mission Control while it is open closes it again; a button's action list
  fills in a moment after the bars appear, so never gate on it; and Mission Control
  does not open at all while the screen is locked.
- Moving a window between Spaces is not a feature, deliberately: every private
  call for it is shut on macOS 15, and the one thing that does work — dragging its
  thumbnail in Mission Control — landed from a probe and from a one-shot command
  but not reliably from the overlay, so it was written, measured and taken out.
  `docs/mechanisms.md` records what was learned; do not re-add it without solving
  that.
- Paths: use `FileManager.url(for:in:appropriateFor:create:)`. Never hardcode
  `~/Library/...` or assume the app bundle location.
- Target is Apple Silicon; do not add x86-specific workarounds.

## Git

- Branch from `main`: `feat/<slug>`, `fix/<slug>`.
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `test:`, `docs:`, `chore:`.
- Subject line in the imperative, ≤72 chars, no trailing period.
- One logical change per commit. Do not mix a refactor with a behaviour change.

## Boundaries

Do not, without explicit approval in the current conversation:

- push, force-push, merge, rebase onto `main`, or amend a pushed commit;
- run `git reset --hard`, `git clean -fdx`, or delete uncommitted work;
- edit `Package.resolved`, CI workflows, signing settings, or `Info.plist`
  version numbers;
- add, upgrade, or remove a dependency;
- commit anything resembling a key, token, certificate, or `.p12`;
- disable a lint rule, add `// swiftlint:disable`, or mark a test as skipped.

Secrets live in the Keychain or in `.env` (gitignored). Never in source, never
in tests, never in a commit message.

## Working style

- Read the surrounding code before writing. Match local conventions over
  general Swift idiom when the two conflict.
- Make the smallest change that solves the problem. Do not refactor adjacent
  code, rename things, or "clean up" files you were not asked to touch.
- If the request is ambiguous or the codebase contradicts it, stop and ask.
  A question is cheaper than a wrong 500-line diff.
- Report honestly. If `make check` fails and you could not fix it, say exactly
  what failed. Do not describe work as complete when it is not.
- When you discover something durable about this codebase — a non-obvious
  invariant, a gotcha — propose adding it to this file.