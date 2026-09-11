import Foundation
import MLX
import Testing

@testable import LTX2

@Suite("the vocoder reproduces the reference's waveform, both generators and the resampler")
struct VocoderParityTests {
    static func loaded(_ fixture: [String: MLXArray]) throws -> LTX2Vocoder {
        let vocoder = LTX2Vocoder(
            generator: LTX2VocoderGeneratorLayout(
                inputChannels: 128, hiddenChannels: 128, outputChannels: 2,
                kernels: [11, 4, 4, 4, 4, 4], factors: [5, 2, 2, 2, 2, 2]),
            extender: LTX2VocoderGeneratorLayout(
                inputChannels: 128, hiddenChannels: 64, outputChannels: 2,
                kernels: [12, 11, 4, 4, 4], factors: [6, 5, 2, 2, 2]))
        try vocoder.load(weights: fixture.filter { !$0.key.hasPrefix("in.") && !$0.key.hasPrefix("out.") })
        return vocoder
    }

    @Test("the first generator makes the reference's 16 kHz waveform, 160 samples a mel frame")
    func firstStage() throws {
        let fixture = try Fixture.load("vocoder")
        let vocoder = try Self.loaded(fixture)
        let mel = try #require(fixture["in.mel"])
        let stacked = mel.transposed(0, 2, 1, 3).reshaped([1, mel.dim(2), -1])
        let low = vocoder.generator(stacked).transposed(0, 2, 1)
        let expected = try #require(fixture["out.low"])
        #expect(low.shape == [1, 2, 3200])
        #expect(low.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(low, expected) < 2e-3)
    }

    @Test("the whole vocoder makes the reference's 48 kHz waveform, clamped")
    func wholeVocoder() throws {
        let fixture = try Fixture.load("vocoder")
        let vocoder = try Self.loaded(fixture)
        let waveform = vocoder(try #require(fixture["in.mel"]))
        let expected = try #require(fixture["out.waveform"])
        #expect(waveform.shape == [1, 2, 9600])
        #expect(waveform.shape == expected.shape)
        #expect(Fixture.maxAbsoluteDifference(waveform, expected) < 5e-3)
    }

    @Test("the Hann resampler's taps are the reference's formula")
    func hannTaps() {
        let taps = LTX2HannResampler.filter
        #expect(taps.count == 43)
        #expect(abs(taps[21] - 0.99 / 3) < 1e-6, "the centre tap is rolloff over the ratio")
        #expect(abs(taps[0]) < 1e-6 && abs(taps[42]) < 1e-6, "the ends are windowed to nothing")
    }
}
