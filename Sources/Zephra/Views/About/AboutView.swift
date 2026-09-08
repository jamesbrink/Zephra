import SwiftUI

/// The About window: icon, name and version, what Zephra is in two sentences, the two
/// buttons — Acknowledgments and Website — and the copyright, laid out the way the standard
/// panel lays its own out, so it reads as the Mac's About window and not as a page.
///
/// The icon is the one the bundle carries (`NSApp.applicationIconImage`), so a change to the
/// icon set changes it here too. Every string comes from `AppFacts`, which Settings > About
/// reads as well; the two never disagree.
struct AboutView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 128, height: 128)
            Text(AppFacts.name)
                .font(.title2.bold())
                .padding(.top, 6)
            Text(AppFacts.versionLine)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text(AppFacts.summary)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 16)
            HStack(spacing: 10) {
                Button("Acknowledgments…") { openWindow(id: AboutScenes.acknowledgmentsID) }
                Button("Website") { openURL(AppFacts.website) }
            }
            .padding(.top, 18)
            Text(AppFacts.copyright)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 18)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 22)
        .frame(width: 320)
    }
}

#Preview("About") {
    AboutView()
}
