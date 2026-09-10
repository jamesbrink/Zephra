import Foundation

/// The shape of the spatial latent upsampler, as `spatial_upscaler_x2_v1_1_config.json` spells it.
///
/// The pack's file carries more switches than this port reads: `dims`, the two upsample
/// flags, `spatial_scale` and `rational_resampler` choose between the reference's several
/// upsampler heads, and only one of those combinations, three-deep convolutions with a plain
/// pixel shuffle doubling height and width, is what the published weights are for. The reader
/// refuses any other so a differently configured file cannot load into a tree of the wrong
/// shape and pass on key names alone.
public struct LTX2UpsamplerConfiguration: Hashable, Sendable {
    /// Channels in the latent the upsampler reads and writes: the autoencoder's 128.
    public let inChannels: Int
    /// Width of every convolution between the first and the last.
    public let midChannels: Int
    /// Residual blocks before the shuffle, and again after it.
    public let blocksPerStage: Int

    /// The published `spatial_upscaler_x2_v1_1`: 128 in, 1024 through, four blocks a stage.
    public static let x2 = LTX2UpsamplerConfiguration(inChannels: 128, midChannels: 1024, blocksPerStage: 4)

    /// Creates a configuration; the reference's GroupNorm of 32 wants `midChannels` a multiple of 32.
    public init(inChannels: Int, midChannels: Int, blocksPerStage: Int) {
        self.inChannels = inChannels
        self.midChannels = midChannels
        self.blocksPerStage = blocksPerStage
    }

    /// Reads the pack's config file, whose fields sit under a `config` key.
    public init(readingFrom url: URL) throws {
        let data = try Data(contentsOf: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        try self.init(file.config)
    }

    init(_ config: Config) throws {
        guard config.dims == 3, config.spatialUpsample, !config.temporalUpsample,
            !config.rationalResampler, config.spatialScale == 2
        else {
            throw LTX2ConfigurationError.unsupportedUpsampler(
                "only a three-deep, spatial-only, non-rational upsampler at scale 2 is ported")
        }
        self.init(
            inChannels: config.inChannels, midChannels: config.midChannels,
            blocksPerStage: config.numBlocksPerStage)
    }

    struct File: Decodable {
        let config: Config
    }

    struct Config: Decodable {
        let inChannels, midChannels, numBlocksPerStage, dims: Int
        let spatialUpsample, temporalUpsample, rationalResampler: Bool
        let spatialScale: Double
        enum CodingKeys: String, CodingKey {
            case inChannels = "in_channels", midChannels = "mid_channels"
            case numBlocksPerStage = "num_blocks_per_stage", dims
            case spatialUpsample = "spatial_upsample", temporalUpsample = "temporal_upsample"
            case rationalResampler = "rational_resampler", spatialScale = "spatial_scale"
        }
    }
}
