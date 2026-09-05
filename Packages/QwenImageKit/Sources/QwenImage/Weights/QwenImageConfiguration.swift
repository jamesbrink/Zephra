import Foundation

/// Every configuration file a Qwen-Image snapshot carries, read and checked in one go.
///
/// Reading them together, up front, is deliberate: each one is a few hundred bytes, and finding
/// out at weight-loading time that a config is missing or inconsistent wastes the minutes it
/// takes to get there.
public struct QwenImageConfiguration: Hashable, Sendable {
    /// The MMDiT backbone's shape.
    public let transformer: QwenImageTransformerConfiguration
    /// The autoencoder's shape.
    public let vae: QwenImageVAEConfiguration
    /// The language stack's shape.
    public let textEncoder: QwenImageTextEncoderConfiguration
    /// The noise schedule.
    public let scheduler: QwenImageSchedulerConfiguration

    /// Where each component's files live inside a snapshot, matching the published layout.
    public enum Component: String, CaseIterable, Sendable {
        case transformer
        case textEncoder = "text_encoder"
        case vae
        case scheduler
        case tokenizer

        /// The directory this component occupies inside a snapshot.
        public var directoryName: String { rawValue }
    }

    /// Reads and validates the four configuration files under `snapshot`.
    public init(readingFrom snapshot: URL) throws {
        transformer = try Self.decode(
            QwenImageTransformerConfiguration.self,
            from: snapshot, component: .transformer, file: "config.json"
        ).validated()
        vae = try Self.decode(
            QwenImageVAEConfiguration.self,
            from: snapshot, component: .vae, file: "config.json"
        ).validated()
        textEncoder = try Self.decode(
            QwenImageTextEncoderConfiguration.self,
            from: snapshot, component: .textEncoder, file: "config.json"
        ).validated()
        scheduler = try Self.decode(
            QwenImageSchedulerConfiguration.self,
            from: snapshot, component: .scheduler, file: "scheduler_config.json"
        ).validated()
        // The one invariant that spans two files: a token is the latent's channels times the
        // patch's cells, which is why `in_channels` is 64 for a 16-channel latent.
        let patch = transformer.patchSize
        guard transformer.inChannels == vae.zDim * patch * patch else {
            throw QwenImageConfigurationError.channelsDoNotMatchLatent(
                inChannels: transformer.inChannels, latentChannels: vae.zDim, patch: patch)
        }
    }

    /// The image size must be a whole number of patches: the VAE's spatial reduction times
    /// the transformer's patch. The one place the number is derived; the catalog's copy is
    /// checked against it by a test.
    public var sizeAlignment: Int { vae.spatialScale * transformer.patchSize }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from snapshot: URL,
        component: Component,
        file: String
    ) throws -> Value {
        let directory = snapshot.appending(path: component.directoryName)
        let url = directory.appending(path: file)
        guard let data = try? Data(contentsOf: url) else {
            throw QwenImageConfigurationError.missingConfiguration(
                name: "\(component.directoryName)/\(file)", directory: snapshot)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
