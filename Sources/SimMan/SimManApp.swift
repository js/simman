import FluidMenuBarExtra
import SwiftUI

/// SwiftUI's MenuBarExtra window doesn't shrink when its content does, and its resizes jump.
/// FluidMenuBarExtra hosts the content in its own panel that animates to fit.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private let store = Store()
  private var menuBarExtra: FluidMenuBarExtra?

  func applicationDidFinishLaunching(_ notification: Notification) {
    menuBarExtra = FluidMenuBarExtra(title: "SimMan", systemImage: "iphone.gen3") { [store] in
      MenuContent().environment(store)
    }
  }
}

struct MenuContent: View {
  @Environment(Store.self) private var store
  @Environment(\.scenePhase) private var scenePhase

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      if store.snapshot.simulators.isEmpty {
        Text("No booted simulators").foregroundStyle(.secondary)
      }
      ForEach(store.snapshot.simulators) { simulator in
        SimulatorSection(simulator: simulator)
      }
      if let error = store.error {
        Text(error).font(.caption).foregroundStyle(.red).lineLimit(3)
      }
      Divider()
      HStack {
        Text(Project.root.lastPathComponent).font(.caption).foregroundStyle(.secondary)
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

struct SimulatorSection: View {
  @Environment(Store.self) private var store
  let simulator: Simulator
  @State private var showsDetails = false

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        DeviceHubLink(simulator: simulator)
        Spacer()
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
      Text(status).font(.caption).foregroundStyle(.secondary)
      if showsDetails {
        SimulatorDetails(simulator: simulator)
      }
      if case .installed = simulator.app {
        VStack(spacing: 0) {
          ForEach(store.snapshot.worktrees) { worktree in
            WorktreeRow(simulator: simulator, worktree: worktree)
          }
        }
      }
    }
  }

  private var status: String {
    switch simulator.app {
    case .notInstalled:
      return "Elton not installed"
    case .installed(let url, let running):
      let target: String
      if let port = store.pendingPort(for: simulator) {
        target = "Loading :\(port)…"
      } else if let metro = store.snapshot.metro(for: simulator) {
        target = "\(metro.worktree.name) on :\(metro.port)"
      } else if let port = url?.port {
        target = "Last on :\(port), no Metro running"
      } else {
        target = "Never loaded a bundle"
      }
      return running ? target : "\(target) (not running)"
    }
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
      guard let metro else { return }
      Task { await store.point(simulator, at: metro) }
    } label: {
      HStack {
        Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isHighlighted ? highlightedText : isCurrent ? Color.accentColor : .secondary)
        HStack {
          Text(worktree.name).lineLimit(1).truncationMode(.middle)
            .foregroundStyle(isHighlighted ? highlightedText : .primary)
          Spacer()
          if isPending {
            ProgressView().controlSize(.small)
          } else if let metro {
            Text(verbatim: ":\(metro.port)").monospaced()
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
    .disabled(!isSelectable)
    .opacity(metro == nil ? 0.4 : 1)
    .help(worktree.path.path)
    .accessibilityIdentifier("\(simulator.udid)|\(worktree.path.lastPathComponent)")
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
      Text(simulator.name).font(.headline)
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
  let simulator: Simulator

  var body: some View {
    let location = Project.simulatedLocation
    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
      GridRow {
        Text("UUID").foregroundStyle(.secondary)
        Text(verbatim: simulator.udid)
          .lineLimit(1).truncationMode(.middle)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
        FeedbackButton(title: "copy", doneTitle: "copied") {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(simulator.udid, forType: .string)
        }
        .gridColumnAlignment(.trailing)
        .accessibilityIdentifier("\(simulator.udid)|copy-uuid")
      }
      GridRow {
        Text("Location").foregroundStyle(.secondary)
        // Verbatim, so the locale can't turn the decimal points into commas.
        Text(verbatim: "\(location.latitude), \(location.longitude)")
          .textSelection(.enabled)
        FeedbackButton(title: "set", doneTitle: "done") {
          try await Discovery.setLocation(of: simulator, latitude: location.latitude, longitude: location.longitude)
        }
        .accessibilityIdentifier("\(simulator.udid)|set-location")
      }
      GridRow {
        Text("Screenshot").foregroundStyle(.secondary)
        Spacer()
        FeedbackButton(title: "copy", doneTitle: "copied") {
          let png = try await Discovery.screenshot(of: simulator)
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setData(png, forType: .png)
        }
        .accessibilityIdentifier("\(simulator.udid)|copy-screenshot")
      }
    }
    .font(.caption)
  }
}

/// A small button that briefly swaps its title for `doneTitle`, or "failed", once its action finishes.
struct FeedbackButton: View {
  let title: String
  let doneTitle: String
  let action: () async throws -> Void
  @State private var outcome: String?
  @State private var isRunning = false

  var body: some View {
    Button(outcome ?? title) {
      isRunning = true
      Task {
        do {
          try await action()
          outcome = doneTitle
        } catch {
          outcome = "failed"
        }
        isRunning = false
        try? await Task.sleep(for: .seconds(1))
        outcome = nil
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
