import Foundation
import MLX
import Testing
import ZephraMLX

@testable import QwenImage21

/// The doll's house `Tools/dump_transformer.py` dumped: two heads of sixteen, three rotary axes
/// filling one head exactly, a text stream the model's own width — which is the real config's
/// `context_in_dim == inner_dim` — and two layers.
enum TransformerFixture {
    static let configurationJSON = """
        {"attention_head_dim": 16, "axes_dims_rope": [4, 6, 6], "context_in_dim": 32,
         "in_channels": 8, "num_attention_heads": 2, "num_layers": 2, "out_channels": 8,
         "patch_size": 1, "mlp_ratio": 3, "eps": 1e-6, "causal_condition": true}
        """

    /// The grids each dumped layout covers, condition images first and the target last.
    static let shapes: [String: [QwenImage21ImageShape]] = [
        "textOnly": [QwenImage21ImageShape(height: 3, width: 4)],
        "oneReference": [
            QwenImage21ImageShape(height: 2, width: 4), QwenImage21ImageShape(height: 3, width: 4),
        ],
    ]

    static func configuration() throws -> QwenImage21TransformerConfiguration {
        try JSONDecoder()
            .decode(
                QwenImage21TransformerConfiguration.self, from: Data(configurationJSON.utf8)
            )
            .validated()
    }

    /// A model filled from the fixture's own state dict.
    static func model(_ fixture: [String: MLXArray]) throws -> QwenImage21Transformer {
        let model = QwenImage21Transformer(try configuration())
        try PackedWeightLoading.load(
            into: model,
            weights: QwenImage21TransformerWeights.sanitized(
                Fixture.weights(fixture, under: "model.")),
            manifest: nil)
        return model
    }

    /// The layout one dumped forward was run over, from the slot mask it was handed.
    static func layout(_ label: String, in fixture: [String: MLXArray], shapes named: String)
        throws -> QwenImage21JointLayout
    {
        try QwenImage21JointLayout(
            imageSlots: try Fixture.flags(fixture, "\(label).in.imgMask"),
            shapes: try #require(shapes[named]))
    }

    /// The rotary table over that layout, built the way the pipeline builds it.
    static func frequencies(_ layout: QwenImage21JointLayout) throws -> RotaryFrequencies {
        QwenImage21Rope(axesDim: try configuration().axesDimsRope)
            .frequencies(QwenImage21RopePositions(layout))
    }
}
