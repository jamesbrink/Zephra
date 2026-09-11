import AVKit
import SwiftUI

/// A clip, playing: `AVPlayerViewController` over the MP4, looped.
///
/// One player for both surfaces. The Mac's `ClipPlayerView` is the model, and the reason for a
/// representable rather than SwiftUI's `VideoPlayer` is the Mac's — plus one of the phone's:
/// the controller is what gives iOS the full-screen controls, the scrubber and the route
/// button people expect of a video. Whether those controls show is the one thing that differs
/// between the two places a clip appears, which is why it is a flag rather than two files.
///
/// Muted unless the file itself says it has sound. The *file*, never the record's word for it:
/// a clip made by a model with no audio lane has no track to unmute, and a phone that unmuted
/// it would simply be silent with its volume up. LTX-2.5's model with sound is the one that
/// has a track.
struct ClipPlayerView: UIViewControllerRepresentable {
    /// The MP4 on this phone.
    let url: URL
    /// Whether the transport controls show. False on the canvas, where a tap on the clip has
    /// to reach the canvas behind it; true in the viewer, where watching is the whole point.
    let showsControls: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = showsControls
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        let player = AVQueuePlayer()
        controller.player = player
        context.coordinator.play(url, on: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        controller.showsPlaybackControls = showsControls
        guard let player = controller.player as? AVQueuePlayer else { return }
        context.coordinator.play(url, on: player)
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController, coordinator: Loop
    ) {
        coordinator.stop()
    }

    func makeCoordinator() -> Loop { Loop() }

    /// What keeps the clip going round, and what decides whether it makes a sound.
    ///
    /// `AVPlayerLooper` holds the loop and must outlive the call that made it, or the clip
    /// plays once and stops; SwiftUI keeps one coordinator per representable instance, which is
    /// exactly the lifetime wanted.
    final class Loop {
        private var looper: AVPlayerLooper?
        private var playing: URL?

        /// Plays one clip, starting the loop over only when it is a different one: the body
        /// runs again on every state update, and a loop rebuilt each time would never get going.
        func play(_ url: URL, on player: AVQueuePlayer) {
            if playing != url {
                playing = url
                let asset = AVURLAsset(url: url)
                looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: asset))
                player.isMuted = true
                unmuteIfItHasSound(asset, on: player, url: url)
            }
            player.play()
        }

        /// Stops the loop and lets go of it.
        func stop() {
            looper?.disableLooping()
            looper = nil
            playing = nil
        }

        /// Asks the file whether it carries a track, and unmutes only if it does.
        private func unmuteIfItHasSound(
            _ asset: AVURLAsset, on player: AVQueuePlayer, url: URL
        ) {
            Task { [weak self] in
                let tracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []
                // The clip may have been swapped while the tracks were being read; unmuting
                // then would be unmuting the wrong one.
                guard let self, self.playing == url, !tracks.isEmpty else { return }
                player.isMuted = false
            }
        }
    }
}
