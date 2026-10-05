# SimMan

SwiftUI menu bar app (Swift package, no Xcode project). `Model.swift` holds the data types, `Discovery.swift` all host queries, `Store.swift` UI state, `SimManApp.swift` the views, `main.swift` the entry point.

## How it works

- Worktrees: `git worktree list --porcelain` on `Project.root`.
- Metro servers: listening TCP ports (`lsof -iTCP -sTCP:LISTEN`) whose owning process has a worktree root as cwd and answers `GET /status` with `packager-status:running`.
- Current Metro per simulator: newest `timestamp` in `expo.devlauncher.recentlyopenedapps`, read with `simctl spawn <udid> defaults export <container>/Library/Preferences/<bundle-id> -`. Do not switch to socket-based detection: after a dev-menu switch the app keeps sockets open to the Metro it left.
- Switching: `simctl launch --terminate-running-process <udid> <bundle-id> --initialUrl http://127.0.0.1:<port>`. expo-dev-launcher reads `--initialUrl` in `initialUrlFromProcessInfo` (EXDevLauncherController.m). The `exp+elton://expo-development-client/?url=` deep link does not work: elton-app's `ios/Elton/PhoneSceneDelegate.swift` forwards warm-start URLs to `RCTLinkingManager` and bypasses the dev launcher, and a cold start through it shows an "Open in Elton?" alert and lands on the launcher home.

## Verifying

- `swift build && .build/debug/SimMan --dump` prints the snapshot the menu renders.
- `./scripts/bundle.sh` builds `build/SimMan.app`. Drive the menu with System Events: `click menu bar item 1 of menu bar 2` of process "SimMan". Rows carry the accessibility identifier `<udid>|<worktree dir name>`. Check the identifier before clicking, since a click relaunches the app in that simulator.
- Test switching only on a simulator you created. Other booted simulators belong to the user or other agents.
