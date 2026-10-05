import SwiftUI

// `SimMan --dump` prints what the menu would show, for checking discovery from a terminal.
// `SimMan --render <file.png>` draws the menu itself, for checking layout without screen capture.
if CommandLine.arguments.contains("--dump") {
  let snapshot = try await Discovery.snapshot()
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
  let image = await MainActor.run {
    let renderer = ImageRenderer(content: MenuContent().environment(store).background(.white))
    renderer.scale = 2
    return renderer.nsImage
  }
  guard let tiff = image?.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
  else { fatalError("render failed") }
  try png.write(to: URL(filePath: CommandLine.arguments[flag + 1]))
} else {
  // Plain AppKit entry rather than a SwiftUI App: an App needs at least one scene, and SwiftUI opens
  // even a placeholder Settings scene as a window at launch.
  let delegate = AppDelegate()
  NSApplication.shared.delegate = delegate
  NSApplication.shared.run()
}
