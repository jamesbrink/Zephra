import Foundation

/// Every configuration file a Qwen-Image 2.1 snapshot carries, read and checked in one go.
///
/// Reading them together, up front, is deliberate: each one is a few hundred bytes, and finding
/// out at weight-loading time that a config is missing or inconsistent wastes the minutes it
/// takes to get there.
public struct QwenImage21Configuration: Hashable, Sendable {
    /// The rectified-flow transformer's shape.
    public let transformer: QwenImage21TransformerConfiguration
    /// The autoencoder's shape, and the statistics its latents are normalised by.
    public let vae: QwenImage21VAEConfiguration
    /// The Qwen3-VL the prompt is read by, decoder and vision tower.
    public let textEncoder: Qwen3VLTextConfiguration
    /// The noise schedule.
    public let scheduler: QwenImage21SchedulerConfiguration
    /// How a reference picture is brought to the tower.
    public let processor: QwenImage21ProcessorConfiguration

    /// Where each component's files live inside a snapshot, matching the published layout.
    public enum Component: String, CaseIterable, Sendable {
        case transformer
        case textEncoder = "text_encoder"
        case vae
        case scheduler
        case processor

        /// The directory this component occupies inside a snapshot.
        public var directoryName: String { rawValue }
    }

    /// Reads and validates every configuration file under `snapshot`.
    public init(readingFrom snapshot: URL) throws {
        transformer = try Self.decode(
            QwenImage21TransformerConfiguration.self,
            from: snapshot, component: .transformer, file: "config.json"
        ).validated()
        vae = try Self.decode(
            QwenImage21VAEConfiguration.self,
            from: snapshot, component: .vae, file: "config.json"
        ).validated()
        textEncoder = try Self.decode(
            Qwen3VLTextConfiguration.self,
            from: snapshot, component: .textEncoder, file: "config.json"
        ).validated()
        scheduler = try Self.decode(
            QwenImage21SchedulerConfiguration.self,
            from: snapshot, component: .scheduler, file: "scheduler_config.json"
        ).validated()
        processor = try Self.decode(
            QwenImage21ProcessorConfiguration.self,
            from: snapshot, component: .processor, file: "preprocessor_config.json")
        // Two invariants span two files. The text stream the transformer reads is the encoder's
        // own width — 2.1's text projection is square — and a token is one latent cell, since
        // `patch_size` is 1 and there is no patchify anywhere to make up a difference.
        guard transformer.contextInDim == textEncoder.text.hiddenSize else {
            throw QwenImage21ConfigurationError.contextWidthIsNotTheEncoder(
                context: transformer.contextInDim, hidden: textEncoder.text.hiddenSize)
        }
        guard transformer.inChannels == vae.zDim else {
            throw QwenImage21ConfigurationError.channelsDoNotMatchLatent(
                inChannels: transformer.inChannels, latentChannels: vae.zDim)
        }
    }

    /// `model_index.json` beside those directories, when the snapshot carries it.
    ///
    /// Nil rather than throwing, because a packed variant is built from the component
    /// directories alone and never carries one; a file that *is* there and names another
    /// pipeline throws.
    public static func modelIndex(in snapshot: URL) throws -> QwenImage21ModelIndex? {
        let url = snapshot.appending(path: "model_index.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let index = try? JSONDecoder().decode(QwenImage21ModelIndex.self, from: data) else {
            throw QwenImage21ConfigurationError.malformedConfiguration(
                name: "model_index.json", directory: snapshot)
        }
        return try index.validated()
    }

    /// Both image edges must be a multiple of this: the autoencoder's spatial reduction times
    /// two, which is what the reference's `vae_scale_factor * 2` comes to. The one place the
    /// number is derived; the catalog's copy is checked against it by a test.
    public var sizeAlignment: Int { vae.scaleFactorSpatial * 2 }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from snapshot: URL,
        component: Component,
        file: String
    ) throws -> Value {
        let directory = snapshot.appending(path: component.directoryName)
        let url = directory.appending(path: file)
        let name = "\(component.directoryName)/\(file)"
        guard let data = try? Data(contentsOf: url) else {
            throw QwenImage21ConfigurationError.missingConfiguration(
                name: name, directory: snapshot)
        }
        guard let value = try? JSONDecoder().decode(type, from: data) else {
            throw QwenImage21ConfigurationError.malformedConfiguration(
                name: name, directory: snapshot)
        }
        return value
    }
}
