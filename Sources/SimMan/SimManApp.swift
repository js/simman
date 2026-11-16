import FluidMenuBarExtra
import SwiftUI

/// SwiftUI's MenuBarExtra window doesn't shrink when its content does, and its resizes jump.
/// FluidMenuBarExtra hosts the content in its own panel that animates to fit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = Store()
  private var menuBarExtra: FluidMenuBarExtra?
  private var settingsWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.mainMenu = Self.mainMenu()
    menuBarExtra = FluidMenuBarExtra(title: "SimMan", systemImage: "iphone.gen3") { [store] in
      MenuContent().environment(store)
    }
    // Load once up front so the first open usually has simulators to show.
    Task { await store.refresh() }
    // On first launch, or when the saved folder has moved, the menu has nothing to show without a project.
    if store.settings.project == nil {
      showSettings(nil)
    }
  }

  /// Reached through the responder chain, which ends at the app delegate.
  @objc func showSettings(_ sender: Any?) {
    if settingsWindow == nil {
      let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(store)))
      window.title = "SimMan Settings"
      window.styleMask = [.titled, .closable]
      window.isReleasedWhenClosed = false
      window.center()
      settingsWindow = window
    }
    NSApp.activate()
    settingsWindow?.makeKeyAndOrderFront(nil)
  }

  /// An accessory app shows no menu bar, but its main menu still supplies key equivalents,
  /// such as ⌘V in text fields and ⌘W to close a window.
  private static func mainMenu() -> NSMenu {
    let edit = NSMenu(title: "Edit")
    edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
    let window = NSMenu(title: "Window")
    window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

    let menu = NSMenu()
    for submenu in [edit, window] {
      menu.addItem(withTitle: submenu.title, action: nil, keyEquivalent: "").submenu = submenu
    }
    return menu
  }
}

struct MenuContent: View {
  @Environment(Store.self) private var store
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if store.settings.project == nil {
        Text("Choose an Expo project in Settings").foregroundStyle(.secondary)
      } else if store.loadedAt == nil && store.error == nil {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text("Loading simulators…").foregroundStyle(.secondary)
        }
      } else if store.snapshot.simulators.isEmpty {
        Text("No booted simulators").foregroundStyle(.secondary)
      }
      if !store.snapshot.simulators.isEmpty {
        SimulatorList()
      }
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
      }
      Divider()
      HStack(spacing: 6) {
        Label {
          Text(verbatim: store.settings.project?.name ?? "No project")
        } icon: {
          Image(systemName: "folder")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        if store.loadedAt != nil && store.isRefreshing && store.isStale {
          ProgressView().controlSize(.mini)
          Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        IconButton(systemImage: "gearshape") {
          NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        }
        .help("Settings")
        .accessibilityIdentifier("settings")
        IconButton(systemImage: "power") { NSApplication.shared.terminate(nil) }
          .help("Quit SimMan")
      }
      // The glyphs' hover circles reach past the text edge.
      .padding(.trailing, -4)
    }
    .padding(12)
    .frame(width: 360)
    // Poll while the menu is open: switches take a few seconds to land in the dev launcher's recents,
    // and Metro servers come and go. The panel keeps this view alive while closed, so key off its phase.
    .task(id: scenePhase) {
      guard scenePhase == .active else { return }
      while !Task.isCancelled {
        await store.refresh()
        try? await Task.sleep(for: .seconds(2))
      }
    }
  }
}

/// Scrolls once the simulators would make the panel taller than the screen.
struct SimulatorList: View {
  @Environment(Store.self) private var store
  @State private var contentHeight: CGFloat = 0
  /// One simulator is open at a time, so the list stays short.
  @State private var expanded: Simulator.ID?

  var body: some View {
    // Leave room for the footer and a margin above the Dock.
    let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 120
    ScrollView {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(store.snapshot.simulators) { simulator in
          SimulatorSection(
            simulator: simulator,
            isExpanded: Binding(get: { expanded == simulator.id }, set: { expanded = $0 ? simulator.id : nil }))
        }
      }
      // Inset inside the scroll view, so row highlights that reach past the text aren't clipped.
      .padding(.horizontal, 12)
      .padding(.vertical, 3)
      .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: min(contentHeight, maxHeight))
    .padding(.horizontal, -12)
    .padding(.vertical, -3)
  }
}

struct SimulatorSection: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  @Binding var isExpanded: Bool
  @State private var showsIdle = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      SimulatorHeader(simulator: simulator, isExpanded: $isExpanded)
      if isExpanded {
        VStack(alignment: .leading, spacing: 12) {
          if case .installed = simulator.app {
            worktrees
          }
          SimulatorDetails(simulator: simulator)
        }
        // Line up with the name, past the icon.
        .padding(.leading, DeviceIcon.size + 10)
        .padding(.bottom, 8)
      }
    }
  }

  /// Worktrees with a running Metro, then the rest behind a disclosure.
  @ViewBuilder private var worktrees: some View {
    let snapshot = store.snapshot
    let live = snapshot.worktrees.filter { snapshot.metro(for: $0) != nil }
    let idle = snapshot.worktrees.filter { snapshot.metro(for: $0) == nil }
    VStack(alignment: .leading, spacing: 0) {
      if live.isEmpty {
        Text("No Metro running").font(.caption).foregroundStyle(.secondary)
      }
      ForEach(live) { WorktreeRow(simulator: simulator, worktree: $0) }
      if !idle.isEmpty {
        Button {
          showsIdle.toggle()
        } label: {
          HStack(spacing: 4) {
            Text(verbatim: "+ \(idle.count) worktrees without Metro")
            Image(systemName: "chevron.right")
              .font(.caption2.weight(.semibold))
              .rotationEffect(.degrees(showsIdle ? 90 : 0))
          }
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.vertical, 3)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("\(simulator.udid)|idle")
        if showsIdle {
          ForEach(idle) { WorktreeRow(simulator: simulator, worktree: $0) }
        }
      }
    }
  }
}

/// A device glyph in a circle, filled with the accent colour while the app runs on a live Metro,
/// so the simulators that are connected stand out when scanning the list.
struct DeviceIcon: View {
  static let size: CGFloat = 26

  @Environment(Store.self) private var store
  let simulator: Simulator
  let isHighlighted: Bool

  var body: some View {
    let isConnected: Bool = {
      guard case .installed(_, running: true) = simulator.app else { return false }
      return store.snapshot.metro(for: simulator) != nil
    }()
    let fill: Color = isHighlighted ? .white.opacity(isConnected ? 0.35 : 0.15)
      : isConnected ? .accentColor : .primary.opacity(0.08)
    Image(systemName: simulator.name.contains("iPad") ? "ipad" : "iphone")
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(isConnected || isHighlighted ? Color.white : .secondary)
      .frame(width: Self.size, height: Self.size)
      .background(Circle().fill(fill))
  }
}

/// The simulator's row: name, OS and the worktree it's on. Clicking it expands the section.
struct SimulatorHeader: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  @Binding var isExpanded: Bool
  @State private var isHovered = false

  var body: some View {
    let highlightedText = Color(nsColor: .selectedMenuItemTextColor)
    Button {
      isExpanded.toggle()
    } label: {
      HStack(spacing: 8) {
        DeviceIcon(simulator: simulator, isHighlighted: isHovered)
          .padding(.trailing, 2)
        VStack(alignment: .leading, spacing: 1) {
          Text(simulator.name).font(.headline).lineLimit(1)
          Text(verbatim: subtitle).font(.caption)
            .foregroundStyle(isHovered ? highlightedText : .secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 8)
        target
          .foregroundStyle(isHovered ? AnyShapeStyle(highlightedText) : AnyShapeStyle(.tertiary))
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(isHovered ? highlightedText : .secondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
      }
      .foregroundStyle(isHovered ? highlightedText : .primary)
      .padding(.horizontal, 7)
      .padding(.vertical, 5)
      .background(
        RoundedRectangle(cornerRadius: 8)
          .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // As on worktree rows, the highlight runs past the text toward the window edge.
    .padding(.horizontal, -7)
    .onHover { isHovered = $0 }
    .accessibilityIdentifier("\(simulator.udid)|expand")
  }

  /// The worktree the simulator is on, or why it isn't on one.
  @ViewBuilder private var target: some View {
    switch simulator.app {
    case .notInstalled:
      Text("App not installed")
    case .installed(let url, _):
      if let port = store.pendingPort(for: simulator) {
        HStack(spacing: 6) {
          ProgressView().controlSize(.small)
          Text(verbatim: ":\(port)").font(.callout).monospaced()
        }
      } else if let metro = store.snapshot.metro(for: simulator) {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(metro.worktree.name).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(isHovered ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
          Text(verbatim: ":\(metro.port)").font(.callout).monospaced()
            .foregroundStyle(isHovered ? AnyShapeStyle(Color(nsColor: .selectedMenuItemTextColor)) : AnyShapeStyle(.secondary))
        }
      } else if let port = url?.port {
        Text(verbatim: "No Metro on :\(port)")
      } else {
        Text("No bundle loaded")
      }
    }
  }

  private var subtitle: String {
    var parts = [simulator.os]
    if store.snapshot.isAmbiguous(simulator) {
      parts.append(String(simulator.udid.prefix(4)))
    }
    if case .installed(_, running: false) = simulator.app {
      parts.append("Not running")
    }
    return parts.joined(separator: " · ")
  }
}

struct WorktreeRow: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  let worktree: Worktree
  @State private var isHovered = false

  var body: some View {
    let metro = store.snapshot.metro(for: worktree)
    let isCurrent = metro != nil && store.snapshot.metro(for: simulator) == metro
    let isPending = metro != nil && store.pendingPort(for: simulator) == metro?.port
    let isSelectable = metro != nil && !isCurrent
    let isHighlighted = isSelectable && isHovered
    let highlightedText = Color(nsColor: .selectedMenuItemTextColor)

    Button {
      guard let metro, isSelectable else { return }
      Task { await store.point(simulator, at: metro) }
    } label: {
      HStack {
        Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isHighlighted ? highlightedText : isCurrent ? Color.accentColor : .secondary)
        HStack(alignment: .firstTextBaseline) {
          Text(worktree.name).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(isHighlighted ? highlightedText : .primary)
          Spacer()
          if isPending {
            ProgressView().controlSize(.small)
          } else if let metro {
            Text(verbatim: ":\(metro.port)").font(.callout).monospaced()
              .foregroundStyle(isHighlighted ? highlightedText : .secondary)
          }
        }
        // The line box centres cap height, which leaves lowercase branch names looking low.
        .offset(y: -1)
      }
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        RoundedRectangle(cornerRadius: 6)
          .fill(isHighlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    // Let the highlight run out toward the window edge, as menu highlights do, while the text
    // stays aligned with the simulator headers.
    .padding(.horizontal, -7)
    .onHover { isHovered = $0 }
    // Only rows without a Metro are disabled; the current row stays at full strength.
    .disabled(metro == nil)
    .accessibilityAddTraits(isCurrent ? .isSelected : [])
    .opacity(metro == nil ? 0.4 : 1)
    .help(worktree.path.path)
    .accessibilityIdentifier("\(simulator.udid)|\(worktree.path.lastPathComponent)")
  }
}

/// Device Hub (Xcode 27+) selects a device in its main window for `devices://manage/select?id=<udid>`.
/// The route comes from DeviceKit.framework's `DeviceManagementURLActionProvider`; Apple doesn't document it.
/// `devices://device/open` opens a separate floating window per device instead.
@MainActor
func showInDeviceHub(_ simulator: Simulator) async throws {
  let url = URL(string: "devices://manage/select?id=\(simulator.udid)")!
  // Without Device Hub, `open` returns without throwing, so check for a handler first.
  guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { throw CocoaError(.fileNoSuchFile) }
  // macOS 14+ only lets an app hand focus to another app it explicitly yields to.
  NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.dt.Devices")
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = true
  try await NSWorkspace.shared.open(url, configuration: configuration)
}

struct SimulatorDetails: View {
  @Environment(Store.self) private var store
  let simulator: Simulator

  var body: some View {
    let location = store.settings.location
    HStack(spacing: 4) {
      ActionTile(title: "Device Hub", doneTitle: "Opened", systemImage: "macwindow") {
        try await showInDeviceHub(simulator)
      }
      .help("Show in Device Hub")
      .accessibilityIdentifier("\(simulator.udid)|devicehub")
      ActionTile(title: "Screenshot", doneTitle: "Copied", systemImage: "camera") {
        let png = try await Discovery.screenshot(of: simulator)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
      }
      .help("Copy a screenshot")
      .accessibilityIdentifier("\(simulator.udid)|copy-screenshot")
      ActionTile(title: "UUID", doneTitle: "Copied", systemImage: "number") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(simulator.udid, forType: .string)
      }
      .help("Copy \(simulator.udid)")
      .accessibilityIdentifier("\(simulator.udid)|copy-uuid")
      ActionTile(title: "Location", doneTitle: "Set", systemImage: "location") {
        try await Discovery.setLocation(of: simulator, to: location)
      }
      .help("Set location to \(location.text)")
      .accessibilityIdentifier("\(simulator.udid)|set-location")
    }
    // Run the tiles' hover fill out to the edges, as the rows above do.
    .padding(.horizontal, -7)
  }
}

/// A Control Center–style action: a glyph in a circle over a caption, the whole tile clickable.
/// When the action finishes, the glyph and caption briefly show whether it worked.
struct ActionTile: View {
  let title: String
  let doneTitle: String
  let systemImage: String
  let action: () async throws -> Void
  @State private var succeeded: Bool?
  @State private var isRunning = false
  @State private var isHovered = false

  var body: some View {
    Button {
      isRunning = true
      Task {
        do {
          try await action()
          succeeded = true
        } catch {
          succeeded = false
        }
        isRunning = false
        try? await Task.sleep(for: .seconds(1))
        succeeded = nil
      }
    } label: {
      VStack(spacing: 5) {
        ZStack {
          Circle().fill(circleFill)
          if isRunning {
            ProgressView().controlSize(.small)
          } else {
            Image(systemName: glyph)
              .font(.system(size: 13, weight: .medium))
              .foregroundStyle(succeeded == nil ? AnyShapeStyle(.primary) : AnyShapeStyle(.white))
              .contentTransition(.symbolEffect(.replace))
          }
        }
        .frame(width: 30, height: 30)
        Text(succeeded == true ? doneTitle : succeeded == false ? "Failed" : title)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(isHovered ? 0.07 : 0)))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isRunning)
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.15), value: succeeded)
  }

  private var glyph: String {
    switch succeeded {
    case true: "checkmark"
    case false: "xmark"
    case nil: systemImage
    }
  }

  private var circleFill: Color {
    switch succeeded {
    case true: .green
    case false: .red
    case nil: .primary.opacity(isHovered ? 0.16 : 0.09)
    }
  }
}

/// A borderless glyph that gains a round fill on hover, for the footer.
struct IconButton: View {
  let systemImage: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: systemImage)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isHovered ? .primary : .secondary)
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
