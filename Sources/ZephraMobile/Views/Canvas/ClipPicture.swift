import SwiftUI
import ZephraLinkClient
import ZephraStyle

/// A clip playing where its poster would be.
///
/// AVKit plays a file and not a buffer, so the MP4 the Mac sends is written into the phone's
/// temporary directory first, under the name the library knows it by. It is written once: a
/// file already there is the same file, since the Mac never rewrites a clip under a name it
/// has used. A clip that will not arrive says so, exactly as a picture does.
struct ClipPicture: View {
    /// The poster's name in the Mac's library; the clip crosses under it too
    /// (`Command.fetchFile`, which answers a clip's MP4 for its poster).
    let name: String
    @Environment(LinkClient.self) private var client
    @State private var phase = FetchPhase<URL>.fetching

    var body: some View {
        Group {
            if let url = phase.value {
                ClipPlayerView(url: url)
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
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .deletingPathExtension()
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            phase = .ready(destination)
            return
        }
        phase = .fetching
        guard let data = try? await client.file(name: name),
            (try? data.write(to: destination, options: .atomic)) != nil
        else {
            phase = .missing
            return
        }
        phase = .ready(destination)
    }
}
