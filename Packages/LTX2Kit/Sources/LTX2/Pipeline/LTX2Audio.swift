import Foundation

/// A clip's sound as this kit hands it back: float samples, channels interleaved, at the
/// vocoder's rate. The MP4 track is the backend's to write, from exactly this layout.
public struct LTX2Audio: Sendable, Hashable {
    /// Interleaved samples, `frames * channels` of them, in -1...1.
    public let samples: [Float]
    /// How many channels are interleaved; two.
    public let channels: Int
    /// Samples a second per channel; 48 000.
    public let sampleRate: Int

    public init(samples: [Float], channels: Int, sampleRate: Int) {
        self.samples = samples
        self.channels = channels
        self.sampleRate = sampleRate
    }

    /// How long the sound plays, in seconds.
    public var seconds: Double { Double(samples.count / channels) / Double(sampleRate) }
}
