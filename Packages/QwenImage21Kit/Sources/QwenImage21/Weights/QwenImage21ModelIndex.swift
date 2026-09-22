import Foundation

/// `model_index.json`: which class the release means each of its directories to be read as.
///
/// It is read for one reason. A Qwen-Image release and a Qwen-Image 2.1 release have the same
/// five directories with the same file names inside them, and the two architectures differ in
/// ways — no per-block modulation, no patchify, four picture channels — that load cleanly and
/// then make noise. The class names are what tell the two apart before a weight is read.
public struct QwenImage21ModelIndex: Hashable, Sendable, Decodable {
    /// The pipeline the release was written for.
    public let className: String
    /// The library and class named for each component directory, by directory name. Anything
    /// the port does not read is kept rather than dropped, so an unknown entry is visible.
    public let components: [String: Component]

    /// One entry: the library the class lives in, and the class.
    public struct Component: Hashable, Sendable {
        /// `diffusers` or `transformers`.
        public let library: String
        /// The class inside it.
        public let className: String
    }

    /// The pipeline this port implements.
    public static let expectedPipeline = "QwenImage21Pipeline"

    /// The class each component directory must name, for the three that decide the port.
    public static let expectedClasses: [String: String] = [
        "transformer": "QwenImage21Transformer2DModel",
        "vae": "AutoencoderKLQwenImage21",
        "text_encoder": "Qwen3VLForConditionalGeneration",
        "scheduler": "FlowMatchEulerDiscreteScheduler",
    ]

    private struct AnyKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var pipeline = ""
        var components: [String: Component] = [:]
        for key in container.allKeys {
            if key.stringValue == "_class_name" {
                pipeline = try container.decode(String.self, forKey: key)
                continue
            }
            guard !key.stringValue.hasPrefix("_") else { continue }
            // Every component is a two-element array; a null entry means the release ships
            // without that component, which is not this port's release.
            guard let pair = try? container.decode([String?].self, forKey: key),
                pair.count == 2, let library = pair[0], let name = pair[1]
            else { continue }
            components[key.stringValue] = Component(library: library, className: name)
        }
        className = pipeline
        self.components = components
    }

    /// Refuses a release whose pipeline or whose three deciding components are not 2.1's.
    public func validated() throws -> Self {
        guard className == Self.expectedPipeline else {
            throw QwenImage21ConfigurationError.unexpectedComponentClass(
                component: "_class_name", className: className)
        }
        for (component, expected) in Self.expectedClasses {
            guard let found = components[component]?.className, found == expected else {
                throw QwenImage21ConfigurationError.unexpectedComponentClass(
                    component: component, className: components[component]?.className ?? "nothing")
            }
        }
        return self
    }
}
