import Foundation
import MLX
import Testing

@testable import QwenImage

/// This port against the Apache-2.0 reference, tensor by tensor.
///
/// The fixtures come from `Tools/dump_reference.py`. Where the earlier suites assert properties
/// this implementation ought to have, these assert that it agrees with the implementation
/// everyone else's images come from — which is the only claim that actually matters.
@Suite("Reference parity")
struct ReferenceParityTests {
    @Test("rotary tables match the reference at three image shapes")
    func ropeMatchesReference() throws {
        let fixture = try Fixture.load("rope")
        let embedding = QwenImageRotaryEmbedding(theta: 10000, axesDim: [16, 56, 56])
        let shapes: [(String, Int, Int, Int, Int)] = [
            ("small", 1, 4, 4, 3),
            ("wide", 1, 2, 6, 5),
            ("large", 1, 64, 64, 20),
        ]
        for (label, frames, height, width, textLength) in shapes {
            let (image, text) = embedding.frequencies(
                frames: frames, height: height, width: width, textLength: textLength)
            for (stream, table) in [("image", image), ("text", text)] {
                for (part, ours) in [("cos", table.cos), ("sin", table.sin)] {
                    let reference = try #require(fixture["\(label).\(stream).\(part)"])
                    #expect(ours.shape == reference.shape, "\(label).\(stream).\(part) shape")
                    let difference = Fixture.maxAbsoluteDifference(ours, reference)
                    #expect(difference < 1e-5, "\(label).\(stream).\(part) differs by \(difference)")
                }
            }
        }
    }

    @Test("the sigma ladder matches the reference at four settings")
    func schedulerMatchesReference() throws {
        let fixture = try Fixture.load("scheduler")
        let configuration = QwenImageSchedulerConfiguration(
            numTrainTimesteps: 1000,
            shift: 1,
            useDynamicShifting: true,
            baseShift: 0.5,
            maxShift: 0.9,
            baseImageSeqLen: 256,
            maxImageSeqLen: 8192,
            shiftTerminal: 0.02,
            timeShiftType: "exponential"
        )
        for (steps, tokens) in [(4, 4096), (8, 4096), (4, 1024), (20, 9216)] {
            let scheduler = FlowMatchEulerScheduler(
                configuration: configuration, steps: steps, imageSequenceLength: tokens)
            let ours = MLXArray(scheduler.sigmas.map(Float.init))
            let reference = try #require(fixture["steps\(steps).tokens\(tokens).sigmas"])
            #expect(ours.shape == reference.shape, "\(steps) steps at \(tokens) tokens: shape")
            let difference = Fixture.maxAbsoluteDifference(ours, reference)
            #expect(difference < 1e-6, "\(steps) steps at \(tokens) tokens: off by \(difference)")
        }
    }

    @Test("packed latents match the reference permutation")
    func latentPackingMatchesReference() throws {
        let fixture = try Fixture.load("latent_packing")
        let latents = try #require(fixture["latents"])
        let reference = try #require(fixture["packed"])
        let packed = QwenImageLatentPacking.pack(latents)
        #expect(packed.shape == reference.shape)
        #expect(Fixture.maxAbsoluteDifference(packed, reference) == 0)
    }
}
