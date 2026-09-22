import Foundation

/// `processor/preprocessor_config.json`: how a reference picture is brought to the vision
/// tower.
///
/// The numbers here decide how many image slots a picture becomes inside the prompt, which is a
/// count the prompt's own tokenisation depends on: `grid_t * grid_h * grid_w / merge²` copies of
/// `<|image_pad|>`. A patch size or a merge read wrong shifts every token after the picture.
public struct QwenImage21ProcessorConfiguration: Hashable, Sendable, Decodable {
    /// Pixels a vision patch covers along each edge.
    public let patchSize: Int
    /// Patches merged along each edge before the tower's output leaves it.
    public let mergeSize: Int
    /// Frames a patch covers. A still picture is repeated to fill it.
    public let temporalPatchSize: Int
    /// Per-channel mean subtracted after rescaling.
    public let imageMean: [Double]
    /// Per-channel deviation divided out after that.
    public let imageStd: [Double]
    /// What a byte is multiplied by before normalisation: one over 255.
    public let rescaleFactor: Double
    /// Pillow's resampling filter number. Three is bicubic.
    public let resample: Int
    /// The pixel bounds a picture is fitted between.
    public let size: Size

    /// `size`: the shortest and longest edge the fitting allows, in pixels of area.
    public struct Size: Hashable, Sendable, Decodable {
        /// The fewest pixels a fitted picture may cover.
        public let shortestEdge: Int
        /// The most.
        public let longestEdge: Int

        enum CodingKeys: String, CodingKey {
            case shortestEdge = "shortest_edge"
            case longestEdge = "longest_edge"
        }
    }

    /// Latent cells one vision-language image slot stands for: the merge squared.
    public var tokensPerSlot: Int { mergeSize * mergeSize }

    enum CodingKeys: String, CodingKey {
        case patchSize = "patch_size"
        case mergeSize = "merge_size"
        case temporalPatchSize = "temporal_patch_size"
        case imageMean = "image_mean"
        case imageStd = "image_std"
        case rescaleFactor = "rescale_factor"
        case resample
        case size
    }
}
