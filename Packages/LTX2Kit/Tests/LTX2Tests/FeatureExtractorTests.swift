import Foundation
import MLX
import MLXNN
import Testing

@testable import LTX2

/// The feature extractor against diffusers' `LTX2TextConnectors` projection step.
///
/// Seven 32-wide states stand in for the 49 3840-wide ones. What this pins is the order the
/// states are laid side by side (hidden-major, the projection's column order), that each state
/// is normalised over its own width and not over the whole row, that padded positions come out
/// as zeros, and the `sqrt(video / caption)` rescale, which is 1 at this fixture's widths and so
/// is pinned by `scaleFollowsTheWidths` instead.
@Suite("The feature extractor reproduces the reference's projected features")
struct FeatureExtractorTests {
    @Test("the projected features match, padded positions included")
    func featuresMatch() throws {
        let fixture = try Fixture.load("feature_extractor")
        let extractor = LTX2FeatureExtractor(hiddenSize: 32, stateCount: 7, outputSize: 32)
        try extractor.update(
            parameters: ModuleParameters.unflattened(
                LTX2ConnectorWeights.projectionWeights(fixture)),
            verify: .all)
        let stacked = try #require(fixture["in.hidden_states"])  // [2, 12, 32, 7]
        let states = (0..<7).map { stacked[0..., 0..., 0..., $0] }
        let padding = try #require(fixture["in.attention_mask"])
        let reference = try #require(fixture["out.features"])

        let features = extractor(states, padding: padding)

        #expect(features.dtype == .float32)
        #expect(features.shape == reference.shape)
        let difference = Fixture.maxAbsoluteDifference(features, reference)
        #expect(difference < 1e-4, Comment(rawValue: "features differ by \(difference)"))
        // Row 1 has seven pads at the front, and they project to exactly the bias.
        let bias = try #require(fixture["connector.text_embedding_projection.video_aggregate_embed.bias"])
        #expect(Fixture.maxAbsoluteDifference(features[1, 0], bias) < 1e-6)
    }

    @Test("the rescale follows the two widths")
    func scaleFollowsTheWidths() throws {
        // A projection that copies the four inputs into the first four of sixteen outputs, on a
        // state of ones: the RMS norm leaves ones alone, so what comes out is the scale itself,
        // sqrt(16 / 4) = 2.
        let extractor = LTX2FeatureExtractor(hiddenSize: 4, stateCount: 1, outputSize: 16)
        try extractor.update(
            parameters: ModuleParameters.unflattened([
                "aggregate_embed.weight": MLX.concatenated([MLXArray.eye(4), MLXArray.zeros([12, 4])]),
                "aggregate_embed.bias": MLXArray.zeros([16]),
            ]), verify: .all)
        let state = MLXArray.ones([1, 1, 4])
        let features = extractor([state], padding: MLXArray.ones([1, 1], dtype: .int32))
        #expect(Fixture.maxAbsoluteDifference(features[0, 0, ..<4], MLXArray.ones([4]) * 2) < 1e-6)
        #expect(Fixture.maxAbsoluteDifference(features[0, 0, 4...], MLXArray.zeros([12])) < 1e-6)
    }
}
