import Foundation

/// Reads worktrees, Metro servers and simulators from the host. Every query shells out,
/// so a snapshot always reflects the machine as it is right now.
enum Discovery {
  static func snapshot(of project: Project) async throws -> Snapshot {
    let worktrees = try await worktrees(of: project)
    async let metros = metros(in: worktrees)
    async let simulators = simulators(bundleID: project.bundleID)
    return try await Snapshot(worktrees: worktrees, metros: metros, simulators: simulators)
  }

  /// Relaunches the app pointed at `metro`. expo-dev-launcher reads `--initialUrl` at startup
  /// (EXDevLauncherController.m, `initialUrlFromProcessInfo`). The `exp+elton://expo-development-client`
  /// deep link would avoid the restart, but Elton's PhoneSceneDelegate hands warm-start URLs to
  /// RCTLinkingManager directly, so the dev launcher never sees them.
  static func point(_ simulator: Simulator, at metro: MetroServer, bundleID: String) async throws {
    _ = try await run(
      "/usr/bin/xcrun", "simctl", "launch", "--terminate-running-process", simulator.udid, bundleID,
      "--initialUrl", "http://127.0.0.1:\(metro.port)")
  }

  static func setLocation(of simulator: Simulator, to location: Location) async throws {
    // simctl wants `lat,lon` with '.' decimals; Double interpolation is locale-independent.
    _ = try await run(
      "/usr/bin/xcrun", "simctl", "location", simulator.udid, "set", "\(location.latitude),\(location.longitude)")
  }

  /// The full device framebuffer as PNG, unmasked, so rounded-corner displays come out rectangular.
  /// simctl's help offers "-" for stdout, but Xcode 27's simctl writes a file named "-" instead.
  static func screenshot(of simulator: Simulator) async throws -> Data {
    let file = FileManager.default.temporaryDirectory.appending(path: "simman-\(UUID().uuidString).png")
    defer { try? FileManager.default.removeItem(at: file) }
    _ = try await run("/usr/bin/xcrun", "simctl", "io", simulator.udid, "screenshot", file.path)
    return try Data(contentsOf: file)
  }

  // MARK: Worktrees

  static func worktrees(of project: Project) async throws -> [Worktree] {
    let output = try await run("/usr/bin/git", "-C", project.root.path, "worktree", "list", "--porcelain")
    return output.components(separatedBy: "\n\n").compactMap { block in
      var path: URL?
      var branch: String?
      for line in block.split(separator: "\n") {
        if line.hasPrefix("worktree ") {
          path = URL(filePath: String(line.dropFirst("worktree ".count))).standardizedFileURL
        } else if line.hasPrefix("branch refs/heads/") {
          branch = String(line.dropFirst("branch refs/heads/".count))
        }
      }
      return path.map { Worktree(path: $0, branch: branch) }
    }
  }

  // MARK: Metro

  /// A Metro server is a listening port, owned by a process whose cwd is a worktree root,
  /// that answers Metro's `/status` probe. The cwd check drops other dev servers (e.g. a nested
  /// `bff/` Expo project); the probe drops non-Metro ports owned by the same process.
  static func metros(in worktrees: [Worktree]) async throws -> [MetroServer] {
    let listening = try await run("/usr/sbin/lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn", allowFailure: true)
    var portsByPID: [Int32: Set<Int>] = [:]
    for (pid, name) in lsofRecords(listening) {
      if let port = name.split(separator: ":").last.flatMap({ Int($0) }) {
        portsByPID[pid, default: []].insert(port)
      }
    }
    guard !portsByPID.isEmpty else { return [] }

    let pids = portsByPID.keys.map(String.init).joined(separator: ",")
    let cwds = try await run("/usr/sbin/lsof", "-a", "-p", pids, "-d", "cwd", "-Fpn", allowFailure: true)
    let worktreeByPath = Dictionary(uniqueKeysWithValues: worktrees.map { ($0.path, $0) })

    let candidates = lsofRecords(cwds).flatMap { pid, cwd -> [MetroServer] in
      guard let worktree = worktreeByPath[URL(filePath: cwd).standardizedFileURL] else { return [] }
      return portsByPID[pid, default: []].map { MetroServer(port: $0, pid: pid, worktree: worktree) }
    }

    return await withTaskGroup(of: MetroServer?.self) { group in
      for metro in candidates {
        group.addTask { await isMetro(port: metro.port) ? metro : nil }
      }
      var found: [MetroServer] = []
      for await metro in group { if let metro { found.append(metro) } }
      return found.sorted { $0.port < $1.port }
    }
  }

  private static func isMetro(port: Int) async -> Bool {
    var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/status")!)
    request.timeoutInterval = 1
    guard let (data, _) = try? await URLSession.shared.data(for: request) else { return false }
    return String(decoding: data, as: UTF8.self) == "packager-status:running"
  }

  /// Pairs each `n` field in `lsof -F pn` output with the `p` field of the process it belongs to.
  private static func lsofRecords(_ output: String) -> [(pid: Int32, name: String)] {
    var pid: Int32?
    var records: [(Int32, String)] = []
    for line in output.split(separator: "\n") {
      switch line.first {
      case "p": pid = Int32(line.dropFirst())
      case "n": if let pid { records.append((pid, String(line.dropFirst()))) }
      default: break
      }
    }
    return records
  }

  // MARK: Simulators

  private struct DeviceList: Decodable {
    struct Device: Decodable {
      let udid: String
      let name: String
    }
    let devices: [String: [Device]]
  }

  static func simulators(bundleID: String) async throws -> [Simulator] {
    let json = try await run("/usr/bin/xcrun", "simctl", "list", "devices", "booted", "-j")
    let devices = try JSONDecoder().decode(DeviceList.self, from: Data(json.utf8)).devices.values.joined()
    return await withTaskGroup(of: Simulator.self) { group in
      for device in devices {
        group.addTask {
          Simulator(udid: device.udid, name: device.name, app: await appState(of: bundleID, on: device.udid))
        }
      }
      var simulators: [Simulator] = []
      for await simulator in group { simulators.append(simulator) }
      return simulators.sorted { $0.name < $1.name }
    }
  }

  /// The dev launcher records every bundle URL it loads, with a timestamp, under
  /// `expo.devlauncher.recentlyopenedapps` in the app's own defaults. The newest entry is the
  /// Metro the app is on. Open sockets don't work for this: an app switched through the dev menu
  /// keeps connections to the Metro it left.
  private static func appState(of bundleID: String, on udid: String) async -> AppState {
    guard let container = try? await run(
      "/usr/bin/xcrun", "simctl", "get_app_container", udid, bundleID, "data")
    else { return .notInstalled }

    let prefs = container.trimmingCharacters(in: .whitespacesAndNewlines) + "/Library/Preferences/" + bundleID
    // Read through the simulator's cfprefsd rather than the plist file, which can lag behind.
    async let exported = try? run("/usr/bin/xcrun", "simctl", "spawn", udid, "defaults", "export", prefs, "-")
    async let services = try? run("/usr/bin/xcrun", "simctl", "spawn", udid, "launchctl", "list")

    let running = await services?.contains("UIKitApplication:\(bundleID)[") ?? false
    return .installed(bundleURL: await exported.flatMap(lastOpenedURL), running: running)
  }

  private static func lastOpenedURL(fromDefaults plist: String) -> URL? {
    guard
      let defaults = try? PropertyListSerialization.propertyList(from: Data(plist.utf8), format: nil) as? [String: Any],
      let recents = defaults["expo.devlauncher.recentlyopenedapps"] as? [String: [String: Any]]
    else { return nil }

    let newest = recents.values.max {
      ($0["timestamp"] as? Double ?? 0) < ($1["timestamp"] as? Double ?? 0)
    }
    return (newest?["url"] as? String).flatMap(URL.init(string:))
  }

  // MARK: Process

  struct CommandFailed: Error, CustomStringConvertible {
    let command: [String]
    let status: Int32
    var description: String { "\(command.joined(separator: " ")) exited with \(status)" }
  }

  /// `allowFailure` is for lsof, which exits 1 when it matches nothing.
  private static func run(_ command: String..., allowFailure: Bool = false) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global().async {
        let process = Process()
        process.executableURL = URL(filePath: command[0])
        process.arguments = Array(command.dropFirst())
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
          try process.run()
        } catch {
          continuation.resume(throwing: error)
          return
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        if process.terminationStatus == 0 || allowFailure {
          continuation.resume(returning: String(decoding: data, as: UTF8.self))
        } else {
          continuation.resume(throwing: CommandFailed(command: command, status: process.terminationStatus))
        }
      }
    }
  }
}
