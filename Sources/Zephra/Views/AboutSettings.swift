import SwiftUI

/// The version, and the third-party notices bundled with the app. This is the disclosure, so
/// it shows the whole file, laid out by `NoticesView` rather than as raw Markdown; the same
/// notices are the standard About panel's credits, through `AboutPanel`.
struct AboutSettings: View {
    @State private var notices = NoticesDocument(blocks: [])

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Zephra \(Self.version)")
                .font(.headline)
            Text("Local image generation on Apple Silicon.")
                .foregroundStyle(.secondary)
            Divider()
            ScrollView {
                NoticesView(document: notices)
            }
        }
        .padding(18)
        .task {
            // Off the main actor: a few hundred lines, but nothing the tab has to wait for.
            notices = await Task.detached { NoticesDocument.bundled() }.value
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }
}

#Preview("About") {
    AboutSettings()
        .frame(width: 480, height: 360)
}
