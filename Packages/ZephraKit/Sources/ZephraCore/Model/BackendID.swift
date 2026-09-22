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

    /// The FLUX.2 family of text-to-image and image-editing models.
    public static let flux2 = BackendID("flux2")

    /// The LTX-2 family of text-to-video models.
    public static let ltx2 = BackendID("ltx2")

    /// The Wan 2.2 family of text- and image-to-video models.
    public static let wan = BackendID("wan")

    /// The Qwen-Image 2.1 family of text-to-image and reference-conditioned models.
    ///
    /// Spelled with the dot, because the family's own name has one and the string is what a
    /// persisted descriptor carries: `qwen-image` without it would read as the 2512 family
    /// this one replaced, whose backend and kit are gone.
    public static let qwenImage21 = BackendID("qwen-image-2.1")
}
