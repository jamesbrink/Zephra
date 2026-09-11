import ZephraCore

/// One size the Size menu offers, and whether it is the shape of the picture in the well.
///
/// With a picture in the well, every tier also offers that picture's own shape at the tier's
/// cost, so a person who wants a quick clip of a portrait photograph is not made to type one:
/// the quick tier's entry is the photograph's shape at the quick preset's pixel count, the
/// standard tier's at the default's, and so on (`ModelCapabilities.size(matchingAspectOf:budget:)`).
/// It leads its tier, and when it is one of the presets already that preset wears the mark
/// rather than appearing twice.
struct SizeChoice: Hashable {
    var size: ImageSize
    var matchesPicture: Bool

    /// What the menu item says: the size, and that it is the picture's shape when it is.
    var label: String {
        matchesPicture ? "\(size.label) · Matches Picture" : size.label
    }

    /// The presets in their listed order, gathered by tier, faster first, with the picture's
    /// shape leading each tier when `picture` is in the well. A tier's budget is its first
    /// preset's pixel count, the one the model names first as that tier's own.
    static func grouped(
        _ capabilities: ModelCapabilities, picture: ImageSize?
    ) -> [(tier: SizeTier, choices: [SizeChoice])] {
        let presets = capabilities.sizePresets
        let matched = picture.map { picture in
            Set(presets.map(\.pixelCount).compactMap { budget in
                capabilities.size(matchingAspectOf: picture, budget: budget)
            })
        } ?? []
        var offered = Set(presets)
        return SizeTier.allCases.compactMap { tier in
            let sizes = presets.filter { capabilities.tier(of: $0) == tier }
            guard let budget = sizes.first?.pixelCount else { return nil }
            var choices = sizes.map { SizeChoice(size: $0, matchesPicture: matched.contains($0)) }
            if let picture, let shape = capabilities.size(matchingAspectOf: picture, budget: budget),
               !offered.contains(shape)
            {
                offered.insert(shape)
                choices.insert(SizeChoice(size: shape, matchesPicture: true), at: 0)
            }
            return (tier, choices)
        }
    }
}
