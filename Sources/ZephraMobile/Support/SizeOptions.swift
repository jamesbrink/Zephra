import ZephraCore

/// What the Size menu holds: the model's presets gathered by what they cost against its
/// default, with the shape of the picture in the well leading each tier.
///
/// A pure function over the capabilities and the picture, so the menu draws what it is handed
/// and `SizeOptionsTests` can ask the same question without a view. The Mac's `SizeChoice.grouped`
/// is the same rule; both read `ModelCapabilities.tier(of:)` and
/// `size(matchingAspectOf:budget:)`, which are the parts worth sharing.
enum SizeOptions {
    /// The presets in their listed order, gathered by tier, faster first, with `reference`'s
    /// own shape leading each tier when there is a picture in the well. A tier's budget is its
    /// first preset's pixel count, the one the model names first as that tier's own; a shape
    /// that is already a preset marks that preset rather than appearing twice.
    static func grouped(
        capabilities: ModelCapabilities, reference: ImageSize?
    ) -> [(tier: SizeTier, choices: [SizeChoice])] {
        let presets = capabilities.sizePresets
        let matched = reference.map { picture in
            Set(
                presets.map(\.pixelCount).compactMap { budget in
                    capabilities.size(matchingAspectOf: picture, budget: budget)
                })
        } ?? []
        var offered = Set(presets)
        return SizeTier.allCases.compactMap { tier in
            let sizes = presets.filter { capabilities.tier(of: $0) == tier }
            guard let budget = sizes.first?.pixelCount else { return nil }
            var choices = sizes.map { SizeChoice(size: $0, matchesPicture: matched.contains($0)) }
            if let reference,
                let shape = capabilities.size(matchingAspectOf: reference, budget: budget),
                !offered.contains(shape)
            {
                offered.insert(shape)
                choices.insert(SizeChoice(size: shape, matchesPicture: true), at: 0)
            }
            return (tier, choices)
        }
    }
}
