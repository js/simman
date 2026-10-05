import SwiftUI

struct SimManApp: App {
  @State private var store = Store()

  var body: some Scene {
    MenuBarExtra("SimMan", systemImage: "iphone.gen3") {
      MenuContent()
        .environment(store)
    }
    .menuBarExtraStyle(.window)
  }
}

struct MenuContent: View {
  @Environment(Store.self) private var store

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
      }
    }
    .monospaced()
    .padding(12)
    .frame(width: 360)
    // Poll while the window is open: switches take a few seconds to land in the dev launcher's recents,
    // and Metro servers come and go.
    .task {
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

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Text(simulator.name).font(.headline)
        Spacer()
        CopyUDIDButton(udid: simulator.udid)
      }
      Text(status).font(.caption).foregroundStyle(.secondary)
      if case .installed = simulator.app {
        ForEach(store.snapshot.worktrees) { worktree in
          WorktreeRow(simulator: simulator, worktree: worktree)
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

    Button {
      guard let metro else { return }
      Task { await store.point(simulator, at: metro) }
    } label: {
      HStack {
        Image(systemName: isCurrent ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
        Text(worktree.name).lineLimit(1).truncationMode(.middle)
        Spacer()
        if isPending {
          ProgressView().controlSize(.small)
        } else if let metro {
          Text(verbatim: ":\(metro.port)").foregroundStyle(.secondary)
        }
      }
      .padding(.horizontal, 4)
      .padding(.vertical, 2)
      .background(
        RoundedRectangle(cornerRadius: 4)
          .fill(isSelectable && isHovered ? Color.primary.opacity(0.1) : .clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .disabled(!isSelectable)
    .opacity(metro == nil ? 0.4 : 1)
    .help(worktree.path.path)
    .accessibilityIdentifier("\(simulator.udid)|\(worktree.path.lastPathComponent)")
  }
}

struct CopyUDIDButton: View {
  let udid: String
  @State private var copied = false

  var body: some View {
    Button(copied ? "copied" : "uuid") {
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(udid, forType: .string)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(1))
        copied = false
      }
    }
    .buttonStyle(.bordered)
    .controlSize(.mini)
    .help(udid)
    .accessibilityIdentifier("\(udid)|uuid")
  }
}
