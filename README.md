# SimMan

A menu bar app that shows which worktree of an Expo project each booted iOS simulator is loading its bundle from, and points it at another worktree in one click.

## Install

```sh
make install    # release build, copied to /Applications (asks for sudo if needed)
open /Applications/SimMan.app
```

For development, `make build` bundles a debug build into `build/debug/SimMan.app`, and `make run` builds it and relaunches it.

## What it shows

Choose the project folder in Settings, which opens on first launch and from the gear button in the menu. SimMan reads the app's bundle ID from `ios/` or `app.json`. The simulated location for the simulator details is set in the same window.

For each booted simulator: the worktree and Metro port the dev build last loaded, then every worktree of the project. Worktrees with a running Metro can be clicked. Clicking one relaunches the app in that simulator, pointed at that Metro. Worktrees without a Metro are greyed out. Start Metro there yourself and the row lights up within two seconds.

## Limits

- One project at a time, and it must be a git repository.
- A project whose bundle ID is only set in a dynamic `app.config.js` needs `expo prebuild` first, so `ios/` exists.
- Switching restarts the app, so in-app state is lost, as with a dev-menu switch.
- The menu shows the last bundle the dev launcher loaded. After "Go home" in the dev menu it still names that bundle.
