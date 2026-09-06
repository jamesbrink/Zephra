import AVKit
import SwiftUI
import ZephraEngine

/// A clip playing where its poster would be: the system player over the MP4 beside the
/// poster, looping, muted (there is no sound yet), and letterboxed into the same rectangle.
///
/// The player is made when the view appears and dropped when it goes, so a clip plays only
/// while it is on screen. It pauses while the model works: decoding H.264 is the media
/// engine's job and not the GPU's, but a clip going round while a run is in flight is one
/// more thing moving, and the rule on this canvas is that only the run moves.
struct ClipPlayerView: View {
    /// The MP4 to play.
    let url: URL
    /// Whether to hold still, which the canvas sets while the model works.
    var paused = false
    @State private var player: AVQueuePlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear { start() }
            .onDisappear { player?.pause(); player = nil }
            .onChange(of: paused) { _, paused in paused ? player?.pause() : player?.play() }
            .onChange(of: url) { _, _ in start() }
    }

    private func start() {
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer(items: [item])
        queue.isMuted = true
        queue.actionAtItemEnd = .none
        // Loop by seeking rather than through AVPlayerLooper, which wants its own template
        // item and a queue it owns; one item played round is all a poster's clip needs.
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak queue] _ in
            queue?.seek(to: .zero)
            queue?.play()
        }
        player = queue
        if !paused { queue.play() }
    }
}
