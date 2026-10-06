import SwiftUI

struct SettingsView: View {
  @Environment(Store.self) private var store
  @State private var latitudeText = ""
  @State private var longitudeText = ""

  var body: some View {
    let settings = store.settings
    VStack(alignment: .leading, spacing: 20) {
      section("Project") {
        GridRow {
          Text("Folder")
          HStack {
            Text(verbatim: settings.project.map { ($0.root.path as NSString).abbreviatingWithTildeInPath } ?? "None")
              .lineLimit(1).truncationMode(.middle)
              .foregroundStyle(settings.project == nil ? .secondary : .primary)
            Spacer()
            Button("Choose…", action: chooseFolder)
          }
        }
        if let project = settings.project {
          Divider()
          GridRow {
            Text("Bundle ID")
            Text(verbatim: project.bundleID).textSelection(.enabled).foregroundStyle(.secondary)
          }
        }
      } footer: {
        if let error = settings.projectError {
          Text(error).foregroundStyle(.red)
        }
      }
      section("Simulated location") {
        GridRow {
          Text("Latitude")
          TextField("Latitude", text: $latitudeText, prompt: Text(verbatim: "59.914797"))
            .frame(maxWidth: 120)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        Divider()
        GridRow {
          Text("Longitude")
          TextField("Longitude", text: $longitudeText, prompt: Text(verbatim: "10.787715"))
            .frame(maxWidth: 120)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
      } footer: {
        Text(locationProblem ?? "Set from a simulator's details in the menu.")
          .foregroundStyle(locationProblem == nil ? .secondary : Color.red)
      }
    }
    .textFieldStyle(.roundedBorder)
    .padding(20)
    .frame(width: 440)
    .fixedSize()
    .onAppear {
      // Interpolation rather than a formatter, so the locale can't swap '.' for ','.
      latitudeText = "\(settings.location.latitude)"
      longitudeText = "\(settings.location.longitude)"
    }
    .onChange(of: [latitudeText, longitudeText]) {
      if let latitude, let longitude { settings.location = Location(latitude: latitude, longitude: longitude) }
    }
  }

  private var latitude: Double? { Self.degrees(latitudeText, within: 90) }
  private var longitude: Double? { Self.degrees(longitudeText, within: 180) }

  private var locationProblem: String? {
    if latitude == nil { return "Latitude must be a number from -90 to 90." }
    if longitude == nil { return "Longitude must be a number from -180 to 180." }
    return nil
  }

  /// Accepts ',' as the decimal separator too, as typed in locales that use it.
  private static func degrees(_ text: String, within limit: Double) -> Double? {
    let text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
    return Double(text).flatMap { abs($0) <= limit ? $0 : nil }
  }

  /// A titled box of label/value rows, like a grouped form's section. A grouped `Form` isn't used because
  /// it gives text fields a grey fill that turns white on hover.
  private func section<Rows: View, Footer: View>(
    _ title: String, @ViewBuilder rows: () -> Rows, @ViewBuilder footer: () -> Footer
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline)
      GroupBox {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
          rows()
        }
        .padding(8)
      }
      footer().font(.caption).padding(.horizontal, 8)
    }
  }

  /// A standalone panel rather than `fileImporter`, whose sheet is twice the size of this window.
  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.message = "Choose an Expo project folder"
    panel.prompt = "Choose"
    panel.directoryURL = store.settings.project?.root.deletingLastPathComponent()
    panel.begin { response in
      guard response == .OK, let url = panel.url else { return }
      store.settings.chooseProject(at: url)
      Task { await store.refresh() }
    }
  }
}
