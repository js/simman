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
      HStack {
        Text(verbatim: store.settings.project?.name ?? "No project").font(.caption).foregroundStyle(.secondary)
        Button {
          NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
        } label: {
          Image(systemName: "gearshape").font(.caption)
        }
        .buttonStyle(SubtleButtonStyle())
        .help("Settings")
        .accessibilityIdentifier("settings")
        if store.loadedAt != nil && store.isRefreshing && store.isStale {
          ProgressView().controlSize(.mini)
          Text("Refreshing…").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Button("Quit") { NSApplication.shared.terminate(nil) }
          .buttonStyle(SubtleButtonStyle())
      }
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
func showInDeviceHub(_ simulator: Simulator) {
  // macOS 14+ only lets an app hand focus to another app it explicitly yields to.
  NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.dt.Devices")
  let configuration = NSWorkspace.OpenConfiguration()
  configuration.activates = true
  NSWorkspace.shared.open(URL(string: "devices://manage/select?id=\(simulator.udid)")!, configuration: configuration)
}

struct SimulatorDetails: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  /// Every title the buttons below can show, so they all reserve the same width.
  private let buttonTitles = ["show", "copy", "copied", "set", "done", FeedbackButton.failedTitle]

  var body: some View {
    let location = store.settings.location
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
      GridRow {
        Text("Device Hub").foregroundStyle(.secondary)
        Spacer()
        FeedbackButton(title: "show", doneTitle: "show", widthOf: buttonTitles) {
          showInDeviceHub(simulator)
        }
        .accessibilityIdentifier("\(simulator.udid)|devicehub")
      }
      GridRow {
        Text("Screenshot").foregroundStyle(.secondary)
        Spacer()
        FeedbackButton(title: "copy", doneTitle: "copied", widthOf: buttonTitles) {
          let png = try await Discovery.screenshot(of: simulator)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setData(png, forType: .png)
        }
        .accessibilityIdentifier("\(simulator.udid)|copy-screenshot")
      }
      GridRow {
        Text("UUID").foregroundStyle(.secondary)
        Text(verbatim: simulator.udid)
          .lineLimit(1).truncationMode(.middle)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        FeedbackButton(title: "copy", doneTitle: "copied", widthOf: buttonTitles) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(simulator.udid, forType: .string)
        }
        .gridColumnAlignment(.trailing)
        .accessibilityIdentifier("\(simulator.udid)|copy-uuid")
      }
      GridRow {
        Text("Location").foregroundStyle(.secondary)
        Text(verbatim: location.text)
          .textSelection(.enabled)
        FeedbackButton(title: "set", doneTitle: "done", widthOf: buttonTitles) {
          try await Discovery.setLocation(of: simulator, to: location)
        }
        .accessibilityIdentifier("\(simulator.udid)|set-location")
      }
    }
    .font(.caption)
  }
}

/// A small button that briefly swaps its title for `doneTitle`, or "failed", once its action finishes.
/// Its label is as wide as the widest of `widthOf`, so swapping titles doesn't resize it.
struct FeedbackButton: View {
  static let failedTitle = "failed"

  let title: String
  let doneTitle: String
  let widthOf: [String]
  let action: () async throws -> Void
  @State private var outcome: String?
  @State private var isRunning = false

  var body: some View {
    Button {
      isRunning = true
      Task {
        do {
          try await action()
          outcome = doneTitle
        } catch {
          outcome = Self.failedTitle
        }
        isRunning = false
        try? await Task.sleep(for: .seconds(1))
        outcome = nil
      }
    } label: {
      ZStack {
        ForEach(widthOf, id: \.self) { Text($0).hidden() }
        Text(outcome ?? title)
      }
    }
    .disabled(isRunning)
    .buttonStyle(SubtleButtonStyle())
  }
}

/// A faint rounded fill that strengthens on hover and press. Bordered AppKit buttons show no hover state.
struct SubtleButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    HoverLabel(configuration: configuration)
  }

  private struct HoverLabel: View {
    let configuration: Configuration
    @State private var isHovered = false

    var body: some View {
      configuration.label
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
          RoundedRectangle(cornerRadius: 5)
            .fill(Color.primary.opacity(configuration.isPressed ? 0.2 : isHovered ? 0.12 : 0.06)))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
  }
}
