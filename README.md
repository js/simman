# SimMan

A menu bar app that shows which elton-app worktree each booted iOS simulator is loading its bundle from, and points it at another worktree in one click.

## Install

```sh
make install    # release build, copied to /Applications (asks for sudo if needed)
open /Applications/SimMan.app
```

For development, `make build` bundles a debug build into `build/debug/SimMan.app`, and `make run` builds it and relaunches it.

## What it shows

For each booted simulator: the worktree and Metro port Elton last loaded, then every worktree of `~/Projects/elton-app`. Worktrees with a running Metro can be clicked. Clicking one relaunches Elton in that simulator, pointed at that Metro. Worktrees without a Metro are greyed out. Start Metro there yourself and the row lights up within two seconds.

## Limits

- elton-app is hardcoded in `Sources/SimMan/Model.swift`.
- Switching restarts the app, so in-app state is lost, as with a dev-menu switch.
- The menu shows the last bundle the dev launcher loaded. After "Go home" in the dev menu it still names that bundle.
