import Foundation

/// An Expo app whose worktrees and iOS dev build SimMan manages.
struct Project: Hashable, Sendable {
  let root: URL
  let bundleID: String

  var name: String { root.lastPathComponent }

  struct Invalid: Error, CustomStringConvertible {
    let description: String
  }

  /// Reads `root` as an Expo project, or throws why it isn't one.
  init(root: URL) throws {
    let root = root.standardizedFileURL
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw Invalid(description: "\((root.path as NSString).abbreviatingWithTildeInPath) doesn't exist.")
    }
    guard
      let data = try? Data(contentsOf: root.appending(path: "package.json")),
      let package = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw Invalid(description: "\(root.lastPathComponent) has no package.json.") }

    let dependencies = ["dependencies", "devDependencies"].compactMap { package[$0] as? [String: Any] }
    guard dependencies.contains(where: { $0["expo"] != nil }) else {
      throw Invalid(description: "\(root.lastPathComponent)'s package.json doesn't depend on expo.")
    }
    guard let bundleID = Self.bundleID(in: root) else {
      throw Invalid(description: "Found no iOS bundle identifier in \(root.lastPathComponent)'s ios/ or app.json.")
    }
    self.root = root
    self.bundleID = bundleID
  }

  /// A dynamic app.config.js can only be read by running it, so prefer the prebuilt Xcode project.
  /// Extension targets append to the app's identifier, which makes the app's the shortest.
  private static func bundleID(in root: URL) -> String? {
    let ios = root.appending(path: "ios")
    let projects = (try? FileManager.default.contentsOfDirectory(atPath: ios.path))?.filter { $0.hasSuffix(".xcodeproj") } ?? []
    let fromXcode = projects.flatMap { project -> [String] in
      let pbxproj = (try? String(contentsOf: ios.appending(path: "\(project)/project.pbxproj"), encoding: .utf8)) ?? ""
      return pbxproj.matches(of: /PRODUCT_BUNDLE_IDENTIFIER = "?([A-Za-z0-9.\-]+)"?;/).map { String($0.1) }
    }
    if let shortest = fromXcode.min(by: { $0.count < $1.count }) { return shortest }

    guard
      let data = try? Data(contentsOf: root.appending(path: "app.json")),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let expo = json["expo"] as? [String: Any],
      let ios = expo["ios"] as? [String: Any]
    else { return nil }
    return ios["bundleIdentifier"] as? String
  }
}

struct Location: Hashable, Sendable {
  var latitude: Double
  var longitude: Double

  /// Parses the "lat, lon" form `text` produces.
  init?(parsing text: String) {
    let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 2, let latitude = Double(parts[0]), let longitude = Double(parts[1]),
      (-90...90).contains(latitude), (-180...180).contains(longitude)
    else { return nil }
    self.init(latitude: latitude, longitude: longitude)
  }

  init(latitude: Double, longitude: Double) {
    self.latitude = latitude
    self.longitude = longitude
  }

  /// Double interpolation is locale-independent, so this always uses '.' decimals.
  var text: String { "\(latitude), \(longitude)" }
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
  /// The runtime, e.g. "iOS 26.5".
  let os: String
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

  /// True when another simulator has the same name and OS, so only the udid tells them apart.
  func isAmbiguous(_ simulator: Simulator) -> Bool {
    simulators.contains { $0.udid != simulator.udid && $0.name == simulator.name && $0.os == simulator.os }
  }

  func metro(for simulator: Simulator) -> MetroServer? {
    guard case .installed(let url?, _) = simulator.app, let port = url.port else { return nil }
    return metros.first { $0.port == port }
  }
}
