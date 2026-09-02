/// The pixel dimensions of a generated image.
public struct ImageSize: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Width in pixels.
    public let width: Int
    /// Height in pixels.
    public let height: Int

    /// Creates a size from raw pixel dimensions, without checking model constraints.
    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Width divided by height, for laying out a placeholder before any pixels exist.
    public var aspectRatio: Double {
        height == 0 ? 0 : Double(width) / Double(height)
    }

    /// Total pixels, a rough proxy for how long a generation will take.
    public var pixelCount: Int {
        width * height
    }

    /// Rounds both dimensions to the nearest multiple of `alignment`, never dropping below it.
    public func aligned(to alignment: Int) -> ImageSize {
        guard alignment > 0 else { return self }
        return ImageSize(
            width: Self.align(width, to: alignment),
            height: Self.align(height, to: alignment)
        )
    }

    /// How the size reads in the interface, using a true multiplication sign.
    public var label: String {
        "\(width) × \(height)"
    }

    /// Mirrors `label` so a size interpolates cleanly into strings.
    public var description: String {
        label
    }

    private static func align(_ value: Int, to alignment: Int) -> Int {
        let steps = (Double(value) / Double(alignment)).rounded()
        return max(alignment, Int(steps) * alignment)
    }
}
