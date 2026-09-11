import SwiftUI
import ZephraLinkClient
import ZephraStyle

/// A clip playing where its poster would be.
///
/// AVKit plays a file and not a buffer, so the MP4 the Mac sends is written into the phone's
/// temporary directory first, under the name the library knows it by. It is written once: a
/// file already there is the same file, since the Mac never rewrites a clip under a name it
/// has used.
struct ClipPicture: View {
    /// The poster's name in the Mac's library; the clip crosses under it too
    /// (`Command.fetchFile`, which answers a clip's MP4 for its poster).
    let name: String
    @Environment(LinkClient.self) private var client
    @State private var url: URL?

    var body: some View {
        Group {
            if let url {
                ClipPlayerView(url: url)
            } else {
                RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous)
                    .fill(.quaternary)
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: ZephraChrome.cardRadius, style: .continuous))
        .task(id: name) { await load() }
        .accessibilityLabel("The newest clip")
    }

    private func load() async {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(name)
            .deletingPathExtension()
            .appendingPathExtension("mp4")
        if FileManager.default.fileExists(atPath: destination.path) {
            url = destination
            return
        }
        url = nil
        guard let data = try? await client.file(name: name) else { return }
        guard (try? data.write(to: destination, options: .atomic)) != nil else { return }
        url = destination
    }
}
