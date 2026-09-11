import Foundation

/// A clip's sound: interleaved float samples, how many channels they interleave, and the rate.
///
/// What a model that makes audio hands the writer beside its frames, and what the stitcher
/// carries from one part to the next. Float32 in the range -1 to 1, channels interleaved
/// (left, right, left, right), which is the one layout `AVAssetWriter` takes as LPCM without a
/// conversion of its own.
public struct AudioTrack: Sendable {
    /// The samples, `frames * channels` of them, interleaved by channel.
    public let samples: [Float]
    /// How many channels are interleaved; 2 for stereo.
    public let channels: Int
    /// Samples per second per channel.
    public let sampleRate: Double

    /// Creates a track, refusing a sample count that is not whole frames.
    public init(samples: [Float], channels: Int, sampleRate: Double) throws {
        guard channels > 0, sampleRate > 0, !samples.isEmpty else { throw MP4WriterError.emptyClip }
        guard samples.count % channels == 0 else {
            throw MP4WriterError.unalignedSamples(channels: channels, got: samples.count)
        }
        self.samples = samples
        self.channels = channels
        self.sampleRate = sampleRate
    }

    /// How many sample frames the track holds: one per channel per instant.
    public var frames: Int { samples.count / channels }

    /// How long the track plays, in seconds.
    public var seconds: Double { Double(frames) / sampleRate }

    /// The track from `seconds` in, or the whole track when nothing is dropped.
    public func dropping(seconds: Double) -> AudioTrack {
        let dropped = min(max(Int((seconds * sampleRate).rounded()), 0), frames)
        guard dropped > 0, dropped < frames else { return dropped == 0 ? self : AudioTrack(unchecked: [], channels: channels, sampleRate: sampleRate) }
        return AudioTrack(unchecked: Array(samples[(dropped * channels)...]), channels: channels, sampleRate: sampleRate)
    }

    /// Two tracks end to end; they must share channels and rate.
    public func appending(_ other: AudioTrack) -> AudioTrack {
        AudioTrack(unchecked: samples + other.samples, channels: channels, sampleRate: sampleRate)
    }

    init(unchecked samples: [Float], channels: Int, sampleRate: Double) {
        self.samples = samples
        self.channels = channels
        self.sampleRate = sampleRate
    }
}
