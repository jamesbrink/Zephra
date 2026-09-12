import AppKit
import SwiftUI
import ZephraEngine
import ZephraSnapshot

/// The buttons on the update banner, and the one thing that decides whether the consequential
/// one may be pressed.
///
/// Installing quits the app, so Update Now is greyed while the engine is doing work that would
/// be thrown away — `UpdateDecision.installBlockedReason` is the whole rule — and the reason is
/// the button's tooltip rather than a sentence added to the strip, which would move the layout
/// about as the engine changes state.
struct UpdateBannerActions: View {
    @Environment(UpdateChecker.self) private var updates: UpdateChecker?
    @Environment(GenerationStore.self) private var store

    var body: some View {
        if let updates {
            switch updates.phase {
            case .available:
                Button(updates.phase.dismissTitle) { updates.later() }
                    .buttonStyle(.bordered)
                Button("Update Now") { updates.updateNow() }
                    .buttonStyle(.borderedProminent)
                    .disabled(blockedReason != nil)
                    .help(blockedReason ?? "Download the update and restart Zephra.")
            case .failed:
                if let image = updates.imageToShow {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([image])
                    }
                    .buttonStyle(.bordered)
                }
                Button(updates.phase.dismissTitle) { updates.later() }
                    .buttonStyle(.bordered)
            case .idle, .checking, .downloading, .ready, .installing:
                EmptyView()
            }
        }
    }

    /// Why Update Now cannot be pressed right now, or nil when it can.
    private var blockedReason: String? {
        UpdateDecision.installBlockedReason(
            engine: store.state,
            hasActiveDownloads: store.downloads.items.contains {
                $0.status == .downloading || $0.status == .queued
            })
    }

    /// One release for the `#Preview`s on both files, so neither invents its own.
    static let sample = ReleaseManifest(
        url: URL(string: "https://zephra-assets.urandom.io/releases/Zephra-0.1.0-202609120231.dmg")!,
        version: "0.1.0", build: "202609120231", sha256: String(repeating: "a", count: 64))
}
