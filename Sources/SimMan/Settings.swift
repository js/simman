import Foundation
import Observation

/// User choices, persisted in the app's defaults.
@MainActor @Observable
final class Settings {
  private static let projectKey = "projectRoot"
  private static let locationKey = "simulatedLocation"
  private let defaults = UserDefaults.standard

  /// Nil until a folder is chosen, or when the saved folder no longer reads as an Expo project.
  private(set) var project: Project?
  /// Why the saved or last chosen folder was rejected.
  private(set) var projectError: String?

  var location: Location {
    didSet { defaults.set(location.text, forKey: Self.locationKey) }
  }

  init() {
    location = defaults.string(forKey: Self.locationKey).flatMap(Location.init(parsing:))
      ?? Location(latitude: 59.914797, longitude: 10.787715)
    if let path = defaults.string(forKey: Self.projectKey) {
      do {
        project = try Project(root: URL(filePath: path))
      } catch {
        projectError = String(describing: error)
      }
    }
  }

  /// Switches to the Expo project at `root`. An invalid folder leaves the current project in place.
  func chooseProject(at root: URL) {
    do {
      project = try Project(root: root)
      projectError = nil
      defaults.set(project?.root.path, forKey: Self.projectKey)
    } catch {
      projectError = String(describing: error)
    }
  }
}
