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

  var body: some View {
    // Leave room for the footer and a margin above the Dock.
    let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 120
    ScrollView {
      VStack(alignment: .leading, spacing: 12) {
        ForEach(Array(store.snapshot.simulators.enumerated()), id: \.element.id) { index, simulator in
          if index > 0 { Divider() }
          SimulatorSection(simulator: simulator)
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
  @State private var showsDetails = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          DeviceHubLink(simulator: simulator)
          Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        Spacer()
        if case .installed = simulator.app {
          WorktreePicker(simulator: simulator).frame(width: 170)
        }
        Button {
          showsDetails.toggle()
        } label: {
          Image(systemName: "chevron.right")
            .font(.caption.weight(.semibold))
            .rotationEffect(.degrees(showsDetails ? 90 : 0))
        }
        .buttonStyle(SubtleButtonStyle())
        .help(showsDetails ? "Hide details" : "Show details")
        .accessibilityIdentifier("\(simulator.udid)|details")
      }
      if showsDetails {
        SimulatorDetails(simulator: simulator)
      }
    }
  }

  /// The OS, and whatever the picker's selection doesn't already say.
  private var subtitle: String {
    var parts = [simulator.os]
    if store.snapshot.isAmbiguous(simulator) {
      parts.append(String(simulator.udid.prefix(4)))
    }
    switch simulator.app {
    case .notInstalled:
      parts.append("App not installed")
    case .installed(_, let running):
      if let port = store.pendingPort(for: simulator) {
        parts.append("Loading :\(port)…")
      }
      if !running {
        parts.append("Not running")
      }
    }
    return parts.joined(separator: " · ")
  }
}

/// A pop-up of the project's worktrees: those with a running Metro, then the rest, dimmed.
/// Picking a Metro relaunches the app in the simulator, pointed at it.
struct WorktreePicker: View {
  @Environment(Store.self) private var store
  let simulator: Simulator

  var body: some View {
    let snapshot = store.snapshot
    let current = snapshot.metro(for: simulator)
    let idle = snapshot.worktrees.filter { snapshot.metro(for: $0) == nil }
    let selection = Binding<Int?>(
      get: { store.pendingPort(for: simulator) ?? current?.port },
      set: { port in
        guard let metro = snapshot.metros.first(where: { $0.port == port }), metro != current else { return }
        Task { await store.point(simulator, at: metro) }
      })

    Picker(selection: selection) {
      if selection.wrappedValue == nil {
        Text(verbatim: placeholder).tag(Int?.none)
      }
      ForEach(snapshot.metros) { metro in
        Text(verbatim: "\(metro.worktree.name)  :\(metro.port)").tag(Int?.some(metro.port))
      }
      if !idle.isEmpty {
        Section("No Metro running") {
          // Negative tags never match a port, and the setter ignores them.
          ForEach(Array(idle.enumerated()), id: \.element.id) { index, worktree in
            Text(verbatim: worktree.name).tag(Int?.some(-1 - index)).selectionDisabled()
          }
        }
      }
    } label: {
      EmptyView()
    }
    .labelsHidden()
    .accessibilityIdentifier("\(simulator.udid)|worktree")
  }

  /// Shown while the simulator isn't on a running Metro.
  private var placeholder: String {
    guard case .installed(let url?, _) = simulator.app, let port = url.port else { return "Choose…" }
    return "No Metro on :\(port)"
  }
}

/// Device Hub (Xcode 27+) selects a device in its main window for `devices://manage/select?id=<udid>`.
/// The route comes from DeviceKit.framework's `DeviceManagementURLActionProvider`; Apple doesn't document it.
/// `devices://device/open` opens a separate floating window per device instead.
struct DeviceHubLink: View {
  let simulator: Simulator
  @State private var isHovered = false

  var body: some View {
    Button {
      // macOS 14+ only lets an app hand focus to another app it explicitly yields to.
      NSApp.yieldActivation(toApplicationWithBundleIdentifier: "com.apple.dt.Devices")
      let configuration = NSWorkspace.OpenConfiguration()
      configuration.activates = true
      NSWorkspace.shared.open(
        URL(string: "devices://manage/select?id=\(simulator.udid)")!, configuration: configuration)
    } label: {
      Text(simulator.name).font(.headline).lineLimit(1)
        .foregroundStyle(isHovered ? Color(nsColor: .selectedMenuItemTextColor) : .primary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
          RoundedRectangle(cornerRadius: 6)
            .fill(isHovered ? Color(nsColor: .selectedContentBackgroundColor) : .clear))
        // Keep the text aligned with the rows; only the highlight extends past it, as on rows.
        .padding(.horizontal, -7)
        .padding(.vertical, -3)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help("Show in Device Hub")
    .accessibilityIdentifier("\(simulator.udid)|devicehub")
  }
}

struct SimulatorDetails: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  /// Every title the buttons below can show, so they all reserve the same width.
  private let buttonTitles = ["copy", "copied", "set", "done", FeedbackButton.failedTitle]

  var body: some View {
    let location = store.settings.location
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
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
