import AVKit
import SwiftUI

/// A clip playing where its poster would be: `AVPlayerView` over the MP4 beside the poster,
/// looping, muted (there is no sound yet), with no transport controls, so a click on it still
/// reaches the canvas — the prompt tuck, the context menu, the viewer's double-click — the
/// way a click on a picture does. SwiftUI's `VideoPlayer` draws controls that take the click.
///
/// It plays on while the model works. Decoding H.264 is the media engine's job and not the
/// GPU's, so it costs the run nothing the app can measure, and a clip that stopped the moment
/// Generate was pressed read as the clip being broken rather than as the run being under way.
struct ClipPlayerView: NSViewRepresentable {
    /// The MP4 to play.
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.play(url)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.play(url)
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the queue player and the looper that feeds it, so the view can be recreated
    /// without either leaking: SwiftUI keeps one coordinator per representable instance.
    @MainActor final class Coordinator {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var url: URL?

        init() { player.isMuted = true }

        /// Plays `url`, starting the loop over only when it is a different clip: `updateNSView`
        /// runs on every rebuild of the canvas, and a loop rebuilt each time would never get going.
        func play(_ url: URL) {
            if self.url != url {
                self.url = url
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
            player.play()
        }

        func stop() {
            player.pause()
            looper = nil
            player.removeAllItems()
        }
    }
}
