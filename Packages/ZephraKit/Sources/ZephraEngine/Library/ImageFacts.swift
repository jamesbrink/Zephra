import Foundation
import ZephraCore

/// The six lines the inspector shows about one image, already formatted.
///
/// Formatting here rather than in the view because the same six lines describe an image on the
/// canvas and an image in the library, and because "how long it took" has enough rules — no
/// answer at all, seconds, minutes, a per-step figure — to be worth testing.
public struct ImageFacts: Hashable, Sendable {
    /// The model that made it, by name when the catalog knows it.
    public let model: String
    /// Pixel dimensions.
    public let size: String
    /// How many denoising steps ran.
    public let steps: String
    /// The seed, as the short label the rest of the interface shows.
    public let seed: String
    /// How long it took, and what that was per step.
    public let took: String
    /// The file's name on disk.
    public let file: String

    /// The facts about a library image. `modelName` is the catalog's name for it, when there is
    /// one; without it the identifier written into the file is shown, which is the honest answer
    /// for an image made by a model this build no longer carries.
    public init(_ item: LibraryItem, modelName: String? = nil) {
        model = modelName ?? item.modelID ?? Self.unknown
        size = Self.label(item.size)
        steps = item.steps.map(String.init) ?? Self.unknown
        seed = item.seed?.shortSeedLabel ?? Self.unknown
        took = Self.tookLabel(seconds: item.durationSeconds ?? 0, steps: item.steps ?? 0)
        file = item.fileName
    }

    /// The facts about an image in memory, which may not have reached the disk yet.
    public init(_ image: GeneratedImage, modelName: String? = nil) {
        model = modelName ?? image.modelID
        size = Self.label(image.settings.size)
        steps = String(image.settings.steps)
        seed = image.settings.seed.shortSeedLabel
        took = Self.tookLabel(seconds: image.duration.seconds, steps: image.settings.steps)
        file = image.fileURL?.lastPathComponent ?? Self.notSaved
    }

    /// How long a generation took, with what that came to per step.
    ///
    /// Minutes past ten of them, because "126.4 s" is a number to be read rather than a duration
    /// to be felt. The per-step figure stays in seconds throughout: it is what a benchmark and a
    /// model's page both quote.
    public static func tookLabel(seconds: Double, steps: Int) -> String {
        guard seconds > 0 else { return unknown }
        let whole = seconds > 600
            ? "\(number(seconds / 60)) min"
            : "\(number(seconds)) s"
        guard steps > 0 else { return whole }
        return "\(whole) \(separator) \(number(seconds / Double(steps))) s/step"
    }

    /// An em-width middle dot, the separator the rest of the interface uses between facts.
    public static let separator = "\u{00B7}"
    /// What is shown where there is no answer.
    public static let unknown = "\u{2014}"
    /// What is shown for an image that has not reached the disk.
    public static let notSaved = "Not saved yet"

    private static func label(_ size: ImageSize) -> String {
        "\(size.width) \u{00D7} \(size.height)"
    }

    private static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
