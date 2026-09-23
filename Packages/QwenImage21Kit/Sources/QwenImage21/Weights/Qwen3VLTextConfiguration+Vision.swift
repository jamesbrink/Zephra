import Foundation

extension Qwen3VLTextConfiguration {
    /// `vision_config`: the tower a reference picture is read by.
    public struct Vision: Hashable, Sendable, Decodable {
        /// Blocks in the tower.
        public let depth: Int
        /// Width of the tower's stream.
        public let hiddenSize: Int
        /// Attention heads per block; the head width is `hiddenSize / numHeads`.
        public let numHeads: Int
        /// Width of the feed-forward's hidden layer.
        public let intermediateSize: Int
        /// Pixels a patch covers along each edge.
        public let patchSize: Int
        /// Frames a patch covers. One picture is repeated to fill it.
        public let temporalPatchSize: Int
        /// Patches merged along each edge before the tower's output leaves it, so four patches
        /// become one image slot in the prompt.
        public let spatialMergeSize: Int
        /// Rows in the learned position table the patch grid is interpolated onto.
        public let numPositionEmbeddings: Int
        /// Width the tower projects onto: the decoder's own.
        public let outHiddenSize: Int
        /// Which blocks' outputs are also fed to the decoder, as DeepStack.
        public let deepstackVisualIndexes: [Int]
        /// The activation inside the tower's feed-forward.
        public let hiddenAct: String

        /// Width of one of the tower's heads.
        public var headDim: Int { hiddenSize / numHeads }

        enum CodingKeys: String, CodingKey {
            case depth
            case hiddenSize = "hidden_size"
            case numHeads = "num_heads"
            case intermediateSize = "intermediate_size"
            case patchSize = "patch_size"
            case temporalPatchSize = "temporal_patch_size"
            case spatialMergeSize = "spatial_merge_size"
            case numPositionEmbeddings = "num_position_embeddings"
            case outHiddenSize = "out_hidden_size"
            case deepstackVisualIndexes = "deepstack_visual_indexes"
            case hiddenAct = "hidden_act"
        }
    }
}
