import Foundation

/// Choosing one of a model's offered sizes for a picture that already exists.
extension ModelCapabilities {
    /// The preset whose shape is nearest `size`'s, or nil when the model offers none.
    ///
    /// What "nearest" means here is the ratio of the ratios, not the difference between them:
    /// the distance is `abs(log(w / h) - log(pw / ph))`, so a picture twice as wide as it is
    /// tall is exactly as far from a square preset as one twice as tall is. Comparing the
    /// ratios directly would make every portrait preset — which lie between 0 and 1 — huddle
    /// together while every landscape one spreads out, and a tall picture would land on a
    /// square.
    ///
    /// Ties go to the earlier preset, so a model that lists its own default first keeps it
    /// whenever nothing beats it. A picture with an edge of zero has no shape to match and
    /// answers nil rather than the first preset.
    public func preset(nearestAspect size: ImageSize) -> ImageSize? {
        guard size.width > 0, size.height > 0 else { return nil }
        let target = log(Double(size.width) / Double(size.height))
        var best: ImageSize?
        var bestDistance = Double.infinity
        for preset in sizePresets where preset.width > 0 && preset.height > 0 {
            let distance = abs(log(Double(preset.width) / Double(preset.height)) - target)
            if distance < bestDistance {
                best = preset
                bestDistance = distance
            }
        }
        return best
    }
}
