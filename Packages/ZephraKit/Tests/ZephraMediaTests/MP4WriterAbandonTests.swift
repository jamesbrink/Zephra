import Foundation
import Testing

@testable import ZephraMedia

/// A clip whose frames fail part way while it has a track of sound.
///
/// The two inputs are fed at once and the writer paces them by pausing whichever is ahead,
/// lifting the pause only through `requestMediaDataWhenReady` — which a cancelled writer never
/// calls again. So the session has to let the sound go when the frames fail, or the encode
/// waits on a callback that will not come. Reaching for `Session` and `FrameAppender` directly
/// is the only way to fail a frame: `MP4Writer.encode` checks the shape of what it is handed
/// before it writes anything.
@Suite("a clip whose frames fail, with sound")
struct MP4WriterAbandonTests {
    @Test("a frame that cannot be made gives up rather than waiting on the audio track", .timeLimit(.minutes(1)))
    func failedFrameWithSound() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "mp4abandon-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        // Thirty seconds of sound against frames that never arrive: the writer pauses the
        // audio input long before the track is done, which is the state the hang needed.
        let session = try MP4Writer.Session(
            to: url, width: 64, height: 32, frameRate: 24,
            audio: try MP4WriterAudioTests.tone(seconds: 30))
        let frames = FrameAppender(count: 720, session: session) { index in
            throw MP4WriterError.encodingFailed("no frame \(index)")
        }
        await #expect(throws: MP4WriterError.self) {
            try await session.run(frames: frames)
        }
    }
}
