import AVKit
import SwiftUI

/// The clip itself: `AVPlayerViewController` over the MP4, looping, with no transport
/// controls, so a tap on it still reaches the canvas.
///
/// The Mac's `ClipPlayerView` in the phone's toolkit, and muted by the same rule: the asset
/// itself is asked whether it has an audio track, never a record's word for it, so the system
/// never shows a volume it cannot change over a silent clip. LTX-2.5's model with sound is the
/// one that has a track.
struct ClipPlayerView: UIViewControllerRepresentable {
    /// The MP4 to play.
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        controller.player = context.coordinator.player
        context.coordinator.play(url)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.play(url)
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController, coordinator: Coordinator
    ) {
        coordinator.stop()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    /// Owns the queue player and the looper that feeds it, so the view can be rebuilt without
    /// either leaking: SwiftUI keeps one coordinator per representable instance.
    @MainActor final class Coordinator {
        let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private var url: URL?

        init() { player.isMuted = true }

        /// Plays `url`, starting the loop over only when it is a different clip: the body runs
        /// again on every state update, and a loop rebuilt each time would never get going.
        func play(_ url: URL) {
            if self.url != url {
                self.url = url
                let asset = AVURLAsset(url: url)
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
                player.isMuted = true
                Task { [weak self] in
                    let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                    guard let self, self.url == url else { return }
                    player.isMuted = tracks.isEmpty
                }
            }
            player.play()
        }

        func stop() {
            player.pause()
            looper?.disableLooping()
            looper = nil
        }
    }
}
