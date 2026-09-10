import Foundation
import ZephraCore

/// Reading a size a person typed: two whole numbers, width first, with whatever sits between
/// them — `800 × 512`, `800x512`, `800 by 512`, `800, 512` — fitted to the model's grid.
///
/// Fitting rather than refusing, because the grid is the model's business and not the
/// person's: a typed 800 × 500 on a grid of 32 is 800 × 512, and the hint under the field
/// says so before Return. Only text with no two numbers in it is refused.
enum SizeEntry {
    /// The size `text` names on `capabilities`' grid, or nil when it names none.
    static func parse(_ text: String, for capabilities: ModelCapabilities) -> ImageSize? {
        guard let typed = typed(text) else { return nil }
        return capabilities.fit(typed)
    }

    /// The two numbers in `text` as they were typed, before any fitting.
    static func typed(_ text: String) -> ImageSize? {
        let numbers = text.split { !$0.isNumber }.compactMap { Int($0) }
        guard numbers.count == 2, numbers.allSatisfy({ $0 > 0 }) else { return nil }
        return ImageSize(width: numbers[0], height: numbers[1])
    }

    /// How a size is spelled in the field: the label's `800 × 512`.
    static func text(_ size: ImageSize) -> String { size.label }

    /// The rule the field follows, for the hint: "Multiples of 32, from 256 to 1024."
    static func rule(for capabilities: ModelCapabilities) -> String {
        let bounds = capabilities.sizeBounds
        return "Multiples of \(capabilities.sizeAlignment), from \(bounds.lowerBound) to \(bounds.upperBound)."
    }
}
