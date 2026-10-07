import SwiftUI

// `SimMan --dump` prints what the menu would show, for checking discovery from a terminal.
// `SimMan --render <file.png>` draws the menu itself, for checking layout without screen capture.
// Run them from the app bundle, so they read the app's settings.
if CommandLine.arguments.contains("--dump") {
  guard let project = Settings().project else { fatalError("no project chosen in Settings") }
  print("project \(project.root.path) \(project.bundleID)")
  let snapshot = try await Discovery.snapshot(of: project)
  for metro in snapshot.metros {
    print("metro :\(metro.port) pid \(metro.pid) -> \(metro.worktree.name)")
  }
  for simulator in snapshot.simulators {
    let target = snapshot.metro(for: simulator).map { "\($0.worktree.name) :\($0.port)" } ?? "none"
    print("sim \(simulator.name) \(simulator.udid) \(simulator.app) -> \(target)")
  }
} else if let flag = CommandLine.arguments.firstIndex(of: "--render") {
  let store = Store()
  await store.refresh()
  // Drawn in an offscreen window rather than with ImageRenderer, which can't draw AppKit-backed views
  // such as the ScrollView.
  let png = await MainActor.run { () -> Data? in
    let window = NSWindow(contentViewController: NSHostingController(rootView: MenuContent().environment(store)))
    // Let SwiftUI settle the list's measured height.
    RunLoop.main.run(until: .now + 0.5)
    guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep.representation(using: .png, properties: [:])
  }
  guard let png else { fatalError("render failed") }
  try png.write(to: URL(filePath: CommandLine.arguments[flag + 1]))
} else {
  // Plain AppKit entry rather than a SwiftUI App: an App needs at least one scene, and SwiftUI opens
  // even a placeholder Settings scene as a window at launch.
  let delegate = AppDelegate()
  NSApplication.shared.delegate = delegate
  NSApplication.shared.run()
}
