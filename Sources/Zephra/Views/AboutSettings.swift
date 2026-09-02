import SwiftUI

/// The version, and the third-party notices bundled with the app. This is the disclosure, so
/// it shows the file verbatim rather than a summary of it.
struct AboutSettings: View {
    @State private var notices = ""

    var body: some View {
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

#Preview("About") {
    AboutSettings()
        .frame(width: 480, height: 360)
}
