import Foundation
import Observation

@MainActor @Observable
final class Store {
  let settings = Settings()
  /// The project `snapshot` was read for.
  private var snapshotProject: Project?
  private(set) var snapshot = Snapshot()
  private(set) var error: String?
  /// When `snapshot` was last read from the host; nil until the first refresh succeeds.
  private(set) var loadedAt: Date?
  private(set) var isRefreshing = false
  /// Simulators relaunched toward a port whose bundle hasn't shown up in the dev launcher's recents yet.
  private(set) var pending: [Simulator.ID: (port: Int, since: Date)] = [:]

  /// True when the snapshot is older than a couple of polling intervals, e.g. after the menu sat closed.
  var isStale: Bool {
    loadedAt.map { $0.timeIntervalSinceNow < -5 } ?? true
  }

  func refresh() async {
    let project = settings.project
    if project != snapshotProject {
      // Show the loading state rather than the previous project's worktrees.
      snapshot = Snapshot()
      snapshotProject = project
      loadedAt = nil
      error = nil
      pending = [:]
    }
    guard let project else {
      loadedAt = .now
      return
    }
    isRefreshing = true
    defer { isRefreshing = false }
    do {
      let snapshot = try await Discovery.snapshot(of: project)
      // The project may have changed while this one was being read.
      guard project == settings.project else { return }
      self.snapshot = snapshot
      loadedAt = .now
      error = nil
    } catch {
      guard project == settings.project else { return }
      self.error = String(describing: error)
    }
    for simulator in snapshot.simulators {
      guard let entry = pending[simulator.id] else { continue }
      if snapshot.metro(for: simulator)?.port == entry.port || entry.since.timeIntervalSinceNow < -30 {
        pending[simulator.id] = nil
      }
    }
  }

  func pendingPort(for simulator: Simulator) -> Int? {
    pending[simulator.id]?.port
  }

  func point(_ simulator: Simulator, at metro: MetroServer) async {
    guard let project = snapshotProject else { return }
    pending[simulator.id] = (metro.port, .now)
    do {
      try await Discovery.point(simulator, at: metro, bundleID: project.bundleID)
    } catch {
      pending[simulator.id] = nil
      self.error = String(describing: error)
    }
    await refresh()
  }
}
