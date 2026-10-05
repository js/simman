# SimMan

## Dev launcher facts the code depends on

- Do not detect the current Metro from sockets. After a dev-menu switch the app keeps sockets open to the Metro it left. The dev launcher's `expo.devlauncher.recentlyopenedapps` timestamps are the reliable source.
- `simctl spawn <udid> defaults read <bundle-id>` fails with "Domain not found". The app's defaults live in its container, so pass the full container plist path.
- Don't find the app process by bundle path. Simulator installs are named by a hash, not `Elton.app`.
- The `exp+elton://expo-development-client/?url=` deep link can't switch Metro. elton-app's `ios/Elton/PhoneSceneDelegate.swift` sends warm-start URLs to `RCTLinkingManager`, so the dev launcher never sees them. A cold start through the link shows an "Open in Elton?" alert and lands on the launcher home. That's why switching relaunches with `--initialUrl`.

## Verifying

- `.build/debug/SimMan --dump` prints the snapshot the menu renders.
- `screencapture` fails here because the terminal has no Screen Recording permission. Instead, `.build/debug/SimMan --render <file.png>` draws the menu offscreen. AppKit-backed controls render as placeholders. To render a hover state, temporarily initialise `isHovered` to true, and revert it before building the app.
- Drive the live menu with System Events (`click menu bar item 1 of menu bar 2` of process "SimMan").
  - The window closes between `osascript` runs, so open it and act on it in one script. Check `count of windows` first, because a click can toggle the window shut.
  - Index into `entire contents`. Element references from `repeat with e in …` read every attribute as empty.
- Rows carry the accessibility identifier `<udid>|<worktree dir name>`, and uuid buttons `<udid>|uuid`. Check the identifier before clicking a row, since a click relaunches the app in that simulator.
- Test switching only on a simulator you created. "🤖 AGENT — do not touch" is driven by other agents, and the user works in "iPhone 17". "simman test" (49ACE056-FEA0-4004-8E71-05A36C637415) was made for testing SimMan. If it's gone, create one and install the Elton dev build from another simulator's `simctl get_app_container <udid> no.vg.lab.zapp app`.
- The user's locale groups digits with spaces. Interpolating numbers into `Text("…")` renders `:8 082`, so use `Text(verbatim:)`.
