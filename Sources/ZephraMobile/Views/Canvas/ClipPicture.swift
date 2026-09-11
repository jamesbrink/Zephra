import SwiftUI
import ZephraStyle

/// A clip playing where its poster would be.
///
/// AVKit plays a file and not a buffer, and the file is the one `LibraryCatalog` keeps: the
/// clip the library watched is the clip the canvas plays, under one budget rather than two, and
/// the phone's temporary directory is left out of it. A clip that will not arrive says so,
/// exactly as a picture does.
struct ClipPicture: View {
    /// The poster's name in the Mac's library; the MP4 sits beside it under the same stem,
    /// which is `VideoSidecar`'s rule and `LibraryCatalog.clipName(of:)`'s.
    let name: String
    @Environment(LibraryCatalog.self) private var catalog
    @State private var phase = FetchPhase<URL>.fetching

    var body: some View {
        Group {
            if let url = phase.value {
                ClipPlayerView(url: url, place: .canvas)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: ZephraChrome.cardRadius, style: .continuous))
            } else {
                PictureUnavailable(isFetching: isFetching)
            }
        }
        .task(id: name) { await load() }
        .accessibilityLabel("The newest clip")
    }

    private var isFetching: Bool {
        if case .fetching = phase { return true }
        return false
    }

    private func load() async {
        phase = .fetching
        guard let url = try? await catalog.url(named: name, isVideo: true) else {
            phase = .missing
            return
        }
        phase = .ready(url)
    }
}
