import SwiftUI

/// The About tab: the icon, the version, what Zephra is, and the way to the third-party
/// notices — the same facts the About window shows, in the Settings window's own shape.
///
/// The notices are not laid out here any more. They are a document of hundreds of lines,
/// and a tab that opened on them read as legal text where a person expected to learn what
/// the app was; they open in the Acknowledgments window instead, the same one the About
/// window's button leads to.
struct AboutSettings: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppFacts.name)
                        .font(.title2.bold())
                    Text(AppFacts.versionLine)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            Text(AppFacts.summary)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Text("Zephra is built on open-source software and open model weights. The Acknowledgments window lists each with its license.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button("Acknowledgments…") { openWindow(id: AboutScenes.acknowledgmentsID) }
                Button("Website") { openURL(AppFacts.website) }
            }
            Spacer(minLength: 0)
            Text(AppFacts.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }
}

#Preview("About") {
    AboutSettings()
        .frame(width: 480, height: 300)
}
