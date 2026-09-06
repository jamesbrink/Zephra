import AVKit
import SwiftUI

/// A clip playing where its poster would be: `AVPlayerView` over the MP4 beside the poster,
/// looping, muted (there is no sound yet), with no transport controls, so a click on it still
/// reaches the canvas — the prompt tuck, the context menu, the viewer's double-click — the
/// way a click on a picture does. SwiftUI's `VideoPlayer` draws controls that take the click.
///
/// It pauses while the model works: decoding H.264 is the media engine's job and not the
/// GPU's, but a clip going round while a run is in flight is one more thing moving, and the
/// rule on this canvas is that only the run moves.
struct ClipPlayerView: NSViewRepresentable {
    /// The MP4 to play.
    let url: URL
    /// Whether to hold still, which the canvas sets while the model works.
    var paused = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.play(url, paused: paused)
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        context.coordinator.play(url, paused: paused)
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

        func play(_ url: URL, paused: Bool) {
            if self.url != url {
                self.url = url
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
            }
            paused ? player.pause() : player.play()
        }

        func stop() {
            player.pause()
            looper = nil
            player.removeAllItems()
        }
    }
}
