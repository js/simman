import Foundation

/// Hardcoded for elton-app until there is a second project to support.
enum Project {
  static let root = URL(filePath: NSString(string: "~/Projects/elton-app").expandingTildeInPath)
  static let bundleID = "no.vg.lab.zapp"
  static let simulatedLocation = (latitude: 59.914797, longitude: 10.787715)
}

struct Worktree: Identifiable, Hashable, Sendable {
  let path: URL
  let branch: String?

  var id: URL { path }
  var name: String { branch ?? path.lastPathComponent }
}

struct MetroServer: Identifiable, Hashable, Sendable {
  let port: Int
  let pid: Int32
  let worktree: Worktree

  var id: Int { port }
}

enum AppState: Hashable, Sendable {
  case notInstalled
  /// `bundleURL` is the dev launcher's most recently opened URL, nil if it has never loaded one.
  case installed(bundleURL: URL?, running: Bool)
}

struct Simulator: Identifiable, Hashable, Sendable {
  let udid: String
  let name: String
  let app: AppState

  var id: String { udid }
}

struct Snapshot: Sendable {
  var worktrees: [Worktree] = []
  var metros: [MetroServer] = []
  var simulators: [Simulator] = []

  func metro(for worktree: Worktree) -> MetroServer? {
    metros.first { $0.worktree == worktree }
  }

  func metro(for simulator: Simulator) -> MetroServer? {
    guard case .installed(let url?, _) = simulator.app, let port = url.port else { return nil }
    return metros.first { $0.port == port }
  }
}
