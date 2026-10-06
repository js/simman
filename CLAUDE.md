# SimMan

## Dev launcher facts the code depends on

- Do not detect the current Metro from sockets. After a dev-menu switch the app keeps sockets open to the Metro it left. The dev launcher's `expo.devlauncher.recentlyopenedapps` timestamps are the reliable source.
- `simctl spawn <udid> defaults read <bundle-id>` fails with "Domain not found". The app's defaults live in its container, so pass the full container plist path.
- Don't find the app process by bundle path. Simulator installs are named by a hash, not `Elton.app`.
- The `exp+elton://expo-development-client/?url=` deep link can't switch Metro. elton-app's `ios/Elton/PhoneSceneDelegate.swift` sends warm-start URLs to `RCTLinkingManager`, so the dev launcher never sees them. A cold start through the link shows an "Open in Elton?" alert and lands on the launcher home. That's why switching relaunches with `--initialUrl`.

## Verifying

- `build/debug/SimMan.app/Contents/MacOS/SimMan --dump` prints the snapshot the menu renders. Run it and `--render` from the bundle, since the chosen project lives in the `com.johansorensen.simman` defaults and a bare `.build` binary reads a different domain.
- `screencapture` fails here because the terminal has no Screen Recording permission. Instead, `--render <file.png>` draws the menu offscreen. AppKit-backed controls render as placeholders. To render a hover state, temporarily initialise `isHovered` to true, and revert it before building the app.
- The menu is a FluidMenuBarExtra panel, which opens only on a real left mouse-down on the status item. System Events' `click` (an AXPress) does nothing, so the menu can't be opened by script without moving the user's pointer. Once it's open, its SwiftUI buttons respond to `perform action "AXPress"`.
  - Index into `entire contents`. Element references from `repeat with e in …` read every attribute as empty.
  - System Events can report 0 windows for an app whose windows CoreGraphics lists on screen. Cross-check with `CGWindowListCopyWindowInfo` filtered by owner PID.
- To see real AppKit controls, such as in the Settings window, temporarily have the app draw the window's frame view with `bitmapImageRepForCachingDisplay(in:)` and `cacheDisplay(in:to:)`, write the PNG, and revert. In-process drawing needs no Screen Recording permission.
- The Settings window is an ordinary window, so System Events can read and drive it. Setting a text field's `value` updates the SwiftUI binding. In the folder panel, setting a row's `selected` doesn't change what Choose returns: it returns the panel's current directory.
- Controls carry accessibility identifiers. Worktree rows are `<udid>|<worktree dir name>`. Per simulator there are also `<udid>|devicehub`, `|details`, `|copy-uuid`, `|set-location` and `|copy-screenshot`. The footer gear is `settings`. Check the identifier before pressing a row, since that relaunches the app in that simulator.
- Test switching only on a simulator you created. "🤖 AGENT — do not touch" is driven by other agents, and the user works in "iPhone 17". "simman test" (49ACE056-FEA0-4004-8E71-05A36C637415) was made for testing SimMan. If it's gone, create one and install the Elton dev build from another simulator's `simctl get_app_container <udid> no.vg.lab.zapp app`.
- The user's locale groups digits with spaces. Interpolating numbers into `Text("…")` renders `:8 082`, so use `Text(verbatim:)`.
