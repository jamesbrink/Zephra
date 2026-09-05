import Foundation
import MLX
import Testing

@testable import ZephraUpscaleRealESRGAN

/// The published checkpoint against the module tree that will be handed it.
///
/// Names and shapes only. The bundled file is float16 and the parity fixtures are float32, so
/// comparing values across the two would measure rounding rather than correctness -- which is
/// why the tolerance claims live in `SRVGGNetParityTests` and this suite makes none.
@Suite("The bundled checkpoint fits the published network exactly")
struct BundledWeightsTests {
    static func published() throws -> [String: MLXArray] {
        SRVGGNetWeights.sanitized(try MLX.loadArrays(url: try BundledWeights.located()))
    }

    @Test("every published tensor lands and every parameter is filled")
    func namesAndShapesLineUp() throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let published = try Self.published()
        let model = SRVGGNet(.generalX4v3)
        let wanted = model.parameters().flattened().reduce(into: [String: [Int]]()) {
            $0[$1.0] = $1.1.shape
        }

        // 34 convolutions with a bias each, and 33 PReLU alphas.
        #expect(published.count == 101)
        let unplaced = Set(published.keys).subtracting(wanted.keys).sorted()
        #expect(
            unplaced.isEmpty,
            Comment(rawValue: "the tree has no place for \(unplaced.joined(separator: ", "))"))
        let unfilled = Set(wanted.keys).subtracting(published.keys).sorted()
        #expect(
            unfilled.isEmpty,
            Comment(rawValue: "nothing fills \(unfilled.joined(separator: ", "))"))

        let mismatched = published.compactMap { name, tensor -> String? in
            guard let expected = wanted[name], expected != tensor.shape else { return nil }
            return "\(name) is \(tensor.shape), the tree wants \(expected)"
        }.sorted()
        #expect(mismatched.isEmpty, Comment(rawValue: mismatched.joined(separator: "; ")))
    }

    @Test("the checkpoint is the 1,213,296-parameter general x4 v3 network")
    func theParameterCountIsTheOneThatNamesTheModel() throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let published = try Self.published()

        // No configuration file ships with this checkpoint, so the parameter count is what says
        // 32 body convolutions rather than the reference default of 16.
        #expect(published.values.reduce(0) { $0 + $1.size } == 1_213_296)
        #expect(published["body.0.weight"]?.shape == [64, 3, 3, 3])
        #expect(published["body.66.weight"]?.shape == [48, 3, 3, 64])
        #expect(published["body.1.weight"]?.shape == [64])
    }

    @Test("the checkpoint loads and enlarges a picture")
    func theCheckpointRuns() throws {
        _ = try #require(BundledWeights.url, "the checkpoint is not in the test bundle")
        let model = SRVGGNet(.generalX4v3)
        try SRVGGNetWeights.load(
            into: model,
            weights: try Self.published().mapValues { $0.asType(.float32) })

        let enlarged = model(Fixture.smooth(edge: 24))

        #expect(enlarged.shape == [1, 96, 96, 3])
        // A trained network on smooth content stays near its input rather than exploding, which
        // is the cheapest sanity check that the transpose went the right way round.
        #expect(MLX.mean(enlarged).item(Float.self) > 0.3)
        #expect(MLX.mean(enlarged).item(Float.self) < 0.7)
    }
}
