/// Names an inference engine family so descriptors can be routed to the code that runs them.
public struct BackendID: Hashable, Sendable, RawRepresentable, ExpressibleByStringLiteral {
    /// The stable, lowercase identifier written into descriptors and persisted settings.
    public let rawValue: String

    /// Creates an identifier from its stable string form.
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Creates an identifier from its stable string form.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Allows an identifier to be written as a bare string literal at call sites.
    public init(stringLiteral value: String) {
        self.rawValue = value
    }

    /// The Z-Image family of text-to-image models.
    public static let zImage = BackendID("z-image")

    /// The Qwen-Image family of text-to-image models.
    public static let qwenImage = BackendID("qwen-image")

    /// The FLUX.2 family of text-to-image and image-editing models.
    public static let flux2 = BackendID("flux2")

    /// The LTX-2 family of text-to-video models.
    public static let ltx2 = BackendID("ltx2")
}
