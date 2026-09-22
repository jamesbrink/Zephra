import CoreGraphics
import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage

/// The ladder's own arithmetic, driven through a stub model whose velocity is `k * latents`,
/// so every latent along the way can be worked out by hand.
@Suite("The denoising loop")
struct DenoiseLoopTests {
    @Test("with no reference every step runs and progress counts from zero")
    func everyStepRuns() throws {
        let stub = Stub(k: 0.5)
        var events: [QwenImageGenerationProgress] = []
        let latents = try Self.run(stub) { events.append($0) }
        #expect(stub.calls == 4)
        #expect(Self.steps(events) == [0, 1, 2, 3])
        let expected = Self.expected(from: Self.noise(), k: 0.5, entering: 0, steps: 4)
        #expect(MLX.allClose(latents, expected, atol: 1e-6).item(Bool.self))
    }

    @Test("with a reference the loop enters at the strength's step and progress still counts against the full ladder")
    func referenceEntersPartWayDown() throws {
        let autoencoder = try LatentPreviewTests.autoencoder()
        let stub = Stub(k: 0.5)
        var events: [QwenImageGenerationProgress] = []
        let reference = QwenImageDenoiseLoop.Reference(
            image: try Self.solidImage(edge: 16), strength: 0.5, width: 16, height: 16)
        let latents = try Self.run(stub, reference: reference, autoencoder: autoencoder) {
            events.append($0)
        }
        // 0.5 of four steps is two, so the loop enters at step 2 and reports 2 and 3 of 4.
        #expect(stub.calls == 2)
        #expect(Self.steps(events) == [2, 3])
        #expect(events.allSatisfy { if case .denoising(_, let total) = $0.stage { total == 4 } else { true } })
        let pixels = try QwenPixelBuffer.pixels(from: try Self.solidImage(edge: 16), width: 16, height: 16)
        let encoded = QwenImageLatentPacking.pack(autoencoder.encode(pixels))
        let start = QwenImageReferenceLatents.mixed(
            reference: encoded, noise: Self.noise(), sigma: Self.scheduler.sigmas[2])
        let expected = Self.expected(from: start, k: 0.5, entering: 2, steps: 4)
        #expect(MLX.allClose(latents, expected, atol: 1e-5).item(Bool.self))
    }

    @Test("the preview closure is never called on the last step")
    func noPreviewOnTheLastStep() throws {
        var previewed: [Int] = []
        _ = try Self.run(Stub(k: 0.5), onPreview: { step, total, _ in
            previewed.append(step)
            #expect(total == 4)
        })
        #expect(previewed == [0, 1, 2])
    }

    @Test("the preview decodes x - sigma_next * v, not the latent")
    func previewDecodesTheEstimateOfTheFinishedLatent() throws {
        let autoencoder = try LatentPreviewTests.autoencoder()
        var frames: [Int: QwenImageLatentPreview] = [:]
        _ = try Self.run(Stub(k: 0.5), autoencoder: autoencoder, onPreview: { step, _, frame in
            frames[step] = try? frame()
        })
        for step in 0..<3 {
            let before = Self.expected(from: Self.noise(), k: 0.5, entering: 0, steps: step)
            let after = Self.expected(from: Self.noise(), k: 0.5, entering: 0, steps: step + 1)
            let estimate = after - (before * 0.5) * Float(Self.scheduler.sigmas[step + 1])
            let expected = try QwenImageLatentPreview.make(
                tokens: estimate, latentHeight: 8, latentWidth: 8, autoencoder: autoencoder)
            #expect(frames[step]?.pixels == expected.pixels, "step \(step)")
            let latentItself = try QwenImageLatentPreview.make(
                tokens: after, latentHeight: 8, latentWidth: 8, autoencoder: autoencoder)
            #expect(frames[step]?.pixels != latentItself.pixels, "step \(step) decoded the latent")
        }
    }

    @Test("cancellation between steps throws before the next transformer call")
    func cancellationStopsBeforeTheNextStep() async throws {
        // In a task of its own, so cancelling it cancels nothing the test runner owns.
        let outcome: (calls: Int, cancelled: Bool) = await Task.detached {
            let stub = Stub(k: 0.5, cancelOnCall: 2)
            do {
                _ = try Self.run(stub)
                return (stub.calls, false)
            } catch {
                return (stub.calls, error is CancellationError)
            }
        }.value
        #expect(outcome.cancelled)
        #expect(outcome.calls == 2, "the check at the top of step 2 threw before the third call")
    }
}
