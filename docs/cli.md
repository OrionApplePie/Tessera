# Command line

The commands Tessera answers to, how the background app is run, and where its
log goes. This half stays English: it is read by scripts and pasted into
reports.

- [CLI](#cli)
- [Run The Background App](#run-the-background-app)
- [Lifecycle](#lifecycle)
- [Logs](#logs)

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
tessera space list
tessera space add
tessera space close 2
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
- `space list` lists the Spaces of the display in use, by index, marking the one
  it is showing
- `space add` adds a desktop to that display
- `space close [index]` closes that Space, or the one being shown when no index is
  given

`show`, `toggle`, `quit`, and `restart` talk to the running background app through
`DistributedNotificationCenter`.

Current notification contract:

- show name: `com.tessera.show-switcher`
- toggle name: `com.tessera.toggle-switcher`
- quit name: `com.tessera.quit-app`
- object: `com.tessera`
- receiver suspension behavior: `deliverImmediately`

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
