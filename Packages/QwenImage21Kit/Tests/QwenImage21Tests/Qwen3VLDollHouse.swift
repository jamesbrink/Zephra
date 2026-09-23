import Foundation
import MLX
import MLXNN
import Testing

@testable import QwenImage21

/// The doll's-house Qwen3-VL the dumpers build, in Swift.
///
/// Every ratio the published model has, at a size that commits: four query heads to one
/// key-value head, an interleaved rope section summing to half the head width, four decoder
/// layers so DeepStack's three taps land in the first three and the fourth says the injection
/// stopped, and a four-block tower with three taps of its own. Structure shows at any width,
/// and every way this port could be wrong is structural.
///
/// The configurations are decoded rather than constructed because they have no memberwise
/// initialiser: they exist to be read out of a published `config.json`, and the numbers here
/// are `Tools/dump_text_encoder.py`'s and `Tools/dump_vision.py`'s.
enum Qwen3VLDollHouse {
    static let json = """
        {"image_token_id": 60, "vision_start_token_id": 58, "vision_end_token_id": 59,
         "text_config": {"hidden_size": 32, "intermediate_size": 96, "num_hidden_layers": 4,
           "num_attention_heads": 4, "num_key_value_heads": 1, "head_dim": 8,
           "rms_norm_eps": 1e-06, "rope_theta": 5000000, "vocab_size": 64,
           "hidden_act": "silu", "attention_bias": false,
           "rope_scaling": {"mrope_interleaved": true, "mrope_section": [2, 1, 1],
             "rope_type": "default"}},
         "vision_config": {"depth": 4, "hidden_size": 32, "num_heads": 2,
           "intermediate_size": 64, "in_channels": 3, "patch_size": 4,
           "temporal_patch_size": 2, "spatial_merge_size": 2,
           "num_position_embeddings": 64, "out_hidden_size": 32,
           "deepstack_visual_indexes": [1, 2, 3], "hidden_act": "gelu_pytorch_tanh"}}
        """

    static func configuration() throws -> Qwen3VLTextConfiguration {
        try JSONDecoder().decode(Qwen3VLTextConfiguration.self, from: Data(json.utf8))
    }

    /// A decoder stack holding the fixture's weights, evaluated.
    ///
    /// `prefix` is `model.` in `text_encoder.safetensors` and `joint.language_model.` in
    /// `vision.safetensors`; `norm.weight` is dropped either way, because this port does not
    /// build the norm the pipeline hooks away.
    static func languageModel(
        _ fixture: [String: MLXArray], prefix: String
    ) throws -> Qwen3VLLanguageModel {
        let model = Qwen3VLLanguageModel(try configuration().text)
        try model.update(
            parameters: ModuleParameters.unflattened(weights(fixture, prefix: prefix)),
            verify: .all)
        MLX.eval(model.parameters())
        return model
    }

    /// The fixture's tensors under `prefix`, with that prefix off and the unbuilt norm dropped.
    static func weights(_ fixture: [String: MLXArray], prefix: String) -> [String: MLXArray] {
        fixture.reduce(into: [:]) { kept, entry in
            guard entry.key.hasPrefix(prefix) else { return }
            let path = String(entry.key.dropFirst(prefix.count))
            guard path != "norm.weight" else { return }
            kept[path] = entry.value
        }
    }
}
