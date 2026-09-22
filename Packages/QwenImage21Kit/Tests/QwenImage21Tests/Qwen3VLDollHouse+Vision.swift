import Foundation
import MLX
import MLXNN
import Testing

@testable import QwenImage21

/// The doll's house's vision half: the processor the patchify reads and the tower itself.
extension Qwen3VLDollHouse {
    /// The doll's-house processor: the published means and deviations at the doll's patch size.
    static let processorJSON = """
        {"patch_size": 4, "merge_size": 2, "temporal_patch_size": 2,
         "image_mean": [0.5, 0.5, 0.5], "image_std": [0.5, 0.5, 0.5], "resample": 3,
         "rescale_factor": 0.00392156862745098,
         "size": {"longest_edge": 16777216, "shortest_edge": 65536}}
        """

    static func processor() throws -> QwenImage21ProcessorConfiguration {
        try JSONDecoder().decode(
            QwenImage21ProcessorConfiguration.self, from: Data(processorJSON.utf8))
    }

    /// A tower holding the fixture's weights, evaluated.
    ///
    /// `prefix` is `visual.` in the tower's own dump and `joint.visual.` in the one that reads
    /// a picture and a prompt together.
    static func visionTower(
        _ fixture: [String: MLXArray], prefix: String
    ) throws -> Qwen3VLVisionTower {
        let tower = Qwen3VLVisionTower(try configuration().vision)
        let named = weights(fixture, prefix: prefix).reduce(into: [String: MLXArray]()) {
            $0[Qwen3VLVisionWeights.prefix + $1.key] = $1.value
        }
        try tower.update(
            parameters: ModuleParameters.unflattened(Qwen3VLVisionWeights.sanitized(named)),
            verify: .all)
        MLX.eval(tower.parameters())
        return tower
    }
}
