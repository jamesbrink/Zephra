import AVKit
import SwiftUI

/// A clip, playing.
///
/// `AVPlayerViewController` through a representable rather than SwiftUI's `VideoPlayer`, which
/// is the Mac's rule (`ClipPlayerView`) for the Mac's reasons — and here for one more: the
/// controller is what gives a phone the full-screen controls, the scrubber and the route
/// button people expect of a video on iOS.
///
/// Looped, and muted unless the file itself says it has sound. The *file*, never the record's
/// word for it: a clip made by a model with no audio lane has no track to unmute, and a phone
/// that unmuted it would simply be silent with its volume up.
struct ClipPlayer: UIViewControllerRepresentable {
    /// The MP4 on this phone.
    let url: URL

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        let player = AVQueuePlayer()
        controller.player = player
        controller.videoGravity = .resizeAspect
        context.coordinator.play(url, on: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        guard let player = controller.player as? AVQueuePlayer else { return }
        context.coordinator.play(url, on: player)
    }

    func makeCoordinator() -> Loop { Loop() }

    /// What keeps the clip going round, and what decides whether it makes a sound.
    ///
    /// `AVPlayerLooper` holds the loop; it must outlive the call that made it or the clip
    /// plays once and stops, which is what the coordinator is for.
    final class Loop {
        private var looper: AVPlayerLooper?
        private var playing: URL?

        /// Starts one clip, if it is not the one already going.
        func play(_ url: URL, on player: AVQueuePlayer) {
            guard playing != url else { return }
            playing = url
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.isMuted = true
            player.play()
            unmuteIfItHasSound(url, on: player)
        }

        /// Asks the file whether it carries a track, and unmutes only if it does.
        private func unmuteIfItHasSound(_ url: URL, on player: AVQueuePlayer) {
            Task {
                let tracks = try? await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
                guard let tracks, !tracks.isEmpty else { return }
                await MainActor.run { player.isMuted = false }
            }
        }
    }
}
