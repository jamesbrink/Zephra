import Foundation

/// Every configuration file a FLUX.2 klein snapshot carries, read and checked in one go.
///
/// Reading them together, up front, is deliberate: each one is a few hundred bytes, and finding
/// out at weight-loading time that a config is missing or inconsistent wastes the minutes it
/// takes to get there.
public struct Flux2Configuration: Hashable, Sendable {
    /// The rectified-flow transformer's shape.
    public let transformer: Flux2TransformerConfiguration
    /// The autoencoder's shape.
    public let vae: Flux2VAEConfiguration
    /// The language stack's shape.
    public let textEncoder: Flux2TextEncoderConfiguration
    /// The noise schedule.
    public let scheduler: Flux2SchedulerConfiguration

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
            Flux2TransformerConfiguration.self,
            from: snapshot, component: .transformer, file: "config.json"
        ).validated()
        vae = try Self.decode(
            Flux2VAEConfiguration.self,
            from: snapshot, component: .vae, file: "config.json"
        ).validated()
        textEncoder = try Self.decode(
            Flux2TextEncoderConfiguration.self,
            from: snapshot, component: .textEncoder, file: "config.json"
        ).validated()
        scheduler = try Self.decode(
            Flux2SchedulerConfiguration.self,
            from: snapshot, component: .scheduler, file: "scheduler_config.json"
        )
        // The one invariant that spans two files: the transformer reads a text stream that is
        // the encoder's width times the number of layers tapped.
        let taps = textEncoder.hiddenStateTaps.count
        guard transformer.jointAttentionDim == textEncoder.hiddenSize * taps else {
            throw Flux2ConfigurationError.jointDimIsNotTheTaps(
                joint: transformer.jointAttentionDim, hidden: textEncoder.hiddenSize, taps: taps)
        }
    }

    private static func decode<Value: Decodable>(
        _ type: Value.Type,
        from snapshot: URL,
        component: Component,
        file: String
    ) throws -> Value {
        let directory = snapshot.appending(path: component.directoryName)
        let url = directory.appending(path: file)
        guard let data = try? Data(contentsOf: url) else {
            throw Flux2ConfigurationError.missingConfiguration(
                name: "\(component.directoryName)/\(file)", directory: snapshot)
        }
        return try JSONDecoder().decode(type, from: data)
    }
}
