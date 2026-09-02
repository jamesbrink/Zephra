import AppKit
import SwiftUI

/// Preferences: where images land, what the engine does at launch, and who wrote the code
/// Zephra stands on.
struct SettingsView: View {
    @AppStorage(AppSettings.randomizeSeedEachRun) private var randomizeSeed = AppSettings.initialRandomizeSeedEachRun
    @AppStorage(AppSettings.warmUpOnLaunch) private var warmUpOnLaunch = AppSettings.initialWarmUpOnLaunch
    @State private var notices = ""

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            performance.tabItem { Label("Performance", systemImage: "speedometer") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 480, height: 360)
    }

    private var general: some View {
        Form {
            LabeledContent("Images are saved to") {
                HStack {
                    Text(AppSettings.defaultOutputDirectory.path(percentEncoded: false))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("Open") {
                        NSWorkspace.shared.open(AppSettings.defaultOutputDirectory)
                    }
                }
            }
            Toggle("Pick a new seed for every run", isOn: $randomizeSeed)
            Toggle("Warm up the model after loading", isOn: $warmUpOnLaunch)
        }
        .formStyle(.grouped)
    }

    private var performance: some View {
        Form {
            Text("GPU cache limit and warm-up options land with the engine wiring.")
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zephra \(Self.version)")
                .font(.headline)
            Text("Local image generation on Apple Silicon.")
                .foregroundStyle(.secondary)
            Divider()
            ScrollView {
                Text(notices)
                    .font(.caption)
                    .monospaced()
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .task { notices = Self.loadNotices() }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }

    private static func loadNotices() -> String {
        guard let url = Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "Acknowledgements are in THIRD_PARTY_NOTICES.md in the source repository." }
        return text
    }
}

#Preview("Settings") {
    SettingsView()
}
