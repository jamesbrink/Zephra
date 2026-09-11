import AVKit
import SwiftUI

/// A clip, playing: `AVPlayerViewController` over the MP4, looped.
///
/// One player for both surfaces. The Mac's `ClipPlayerView` is the model, and the reason for a
/// representable rather than SwiftUI's `VideoPlayer` is the Mac's — plus one of the phone's:
/// the controller is what gives iOS the full-screen controls, the scrubber and the route
/// button people expect of a video. Where the clip is showing decides the two things that
/// differ between the places a clip appears — whether the controls show, and whether a pull
/// downwards closes the viewer over it — which is why it is a `Place` rather than two files.
///
/// In the viewer the player's view carries the same `ViewerPullRecognizer` a picture's scroll
/// view does, so a clip drops and closes under the finger exactly as a picture does. The
/// recognizer runs beside AVKit's own and cancels no touch, so a tap still brings the
/// controls up and the scrubber still scrubs.
///
/// Muted unless the file itself says it has sound. The *file*, never the record's word for it:
/// a clip made by a model with no audio lane has no track to unmute, and a phone that unmuted
/// it would simply be silent with its volume up. LTX-2.5's model with sound is the one that
/// has a track.
struct ClipPlayerView: UIViewControllerRepresentable {
    /// The MP4 on this phone.
    let url: URL
    /// Where the clip is showing, which decides what the player does besides play.
    let place: Place

    @Environment(\.viewerGestures) private var gestures

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = place == .viewer
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .clear
        if place == .viewer { controller.view.addGestureRecognizer(context.coordinator.pull) }
        let player = AVQueuePlayer()
        controller.player = player
        context.coordinator.play(url, on: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        // Set on every update, not once: the closure closes over the viewer's state and a
        // stale one would pull on a viewer that has since been rebuilt.
        context.coordinator.pull.onPull = gestures.pulled
        guard let player = controller.player as? AVQueuePlayer else { return }
        context.coordinator.play(url, on: player)
    }

    static func dismantleUIViewController(
        _ controller: AVPlayerViewController, coordinator: Playback
    ) {
        coordinator.stop()
    }

    func makeCoordinator() -> Playback { Playback() }

    /// The two places a clip plays, and what each asks of the player.
    enum Place {
        /// The canvas: no controls, since a tap on the clip has to reach the canvas behind
        /// it, and nothing to pull.
        case canvas
        /// The viewer: the controls, since watching is the whole point, and the pull
        /// downwards that closes it.
        case viewer
    }

    /// What keeps the clip going round, what decides whether it makes a sound, and the pull
    /// that closes the viewer over it.
    ///
    /// `AVPlayerLooper` holds the loop and must outlive the call that made it, or the clip
    /// plays once and stops; SwiftUI keeps one coordinator per representable instance, which is
    /// exactly the lifetime wanted, for the recognizer as much as the loop.
    @MainActor final class Playback {
        /// The pull downwards, attached to the player's view in the viewer alone.
        let pull = ViewerPullRecognizer()
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
