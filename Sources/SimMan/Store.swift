import Foundation
import Observation

@MainActor @Observable
final class Store {
  private(set) var snapshot = Snapshot()
  private(set) var error: String?
  /// Simulators relaunched toward a port whose bundle hasn't shown up in the dev launcher's recents yet.
  private(set) var pending: [Simulator.ID: (port: Int, since: Date)] = [:]

  func refresh() async {
    do {
      snapshot = try await Discovery.snapshot()
      error = nil
    } catch {
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
    pending[simulator.id] = (metro.port, .now)
    do {
      try await Discovery.point(simulator, at: metro)
    } catch {
      pending[simulator.id] = nil
      self.error = String(describing: error)
    }
    await refresh()
  }
}
