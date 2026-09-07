import Foundation
import ZephraCore

/// The lines the inspector shows about one image, already formatted.
///
/// Formatting here rather than in the view because the same seven lines describe an image on the
/// canvas and an image in the library, and because "how long it took" has enough rules — no
/// answer at all, seconds, minutes, a per-step figure — to be worth testing.
public struct ImageFacts: Hashable, Sendable {
    /// The model that made it, by name when the catalog knows it.
    public let model: String
    /// Pixel dimensions.
    public let size: String
    /// How many denoising steps ran.
    public let steps: String
    /// The seed, spelled the way the `SeedFormat` it was built with spells seeds.
    public let seed: String
    /// How long it took, and what that was per step.
    public let took: String
    /// The file's name on disk.
    public let file: String
    /// What it was made larger from, and by how much, or nil when it was not an upscale.
    public let upscaled: String?
    /// How long the clip runs and how many frames it has, or nil for a picture.
    public let length: String?
    /// How far from the reference picture the generation started, to two decimals, or nil when
    /// there was no picture and when the strength was 1 — a model that conditions on the
    /// picture directly had no distance to travel, and a row saying "1.00" says nothing.
    public let referenceStrength: String?
    /// The same number unformatted, for an interface that words some value of it specially:
    /// LTX-2.5 runs the scale the other way and its 0 means the first frame is held exactly,
    /// which reads as a phrase rather than as a number. `length` says which kind of picture
    /// this is, so the caller has both halves of that question.
    public let referenceStrengthValue: Double?
    /// The library file the reference picture came out of, or nil when it came from a file
    /// chooser, a drop, or nowhere at all.
    public let referenceOrigin: String?

    /// The facts about a library image. `modelName` is the catalog's name for it, when there is
    /// one; without it the identifier written into the file is shown, which is the honest answer
    /// for an image made by a model this build no longer carries. `seedFormat` is the
    /// preference the inspector reads; the short label unless the interface says otherwise.
    public init(_ item: LibraryItem, modelName: String? = nil, seedFormat: SeedFormat = .hex) {
        model = modelName ?? item.modelID ?? Self.unknown
        size = Self.label(item.size)
        steps = Self.stepsLabel(item.steps)
        seed = Self.seedLabel(item.seed, as: seedFormat)
        // An upscale's seconds are the network's, not the steps', so the per-step figure that
        // would follow from the parent's step count is left off.
        took = Self.tookLabel(
            seconds: item.durationSeconds ?? 0, steps: item.upscale == nil ? item.steps ?? 0 : 0)
        file = item.fileName
        upscaled = item.upscale.map { "\u{00D7}\($0.factor) from \($0.parent)" }
        length = item.provenance.record.flatMap { record in
            record.frameCount.map { Self.lengthLabel(frames: $0, rate: record.frameRate ?? 24) }
        }
        // The record's own strength is already nil where there was no picture.
        referenceStrengthValue = Self.reportable(item.provenance.record?.referenceStrength)
        referenceStrength = referenceStrengthValue.map(Self.strengthLabel)
        referenceOrigin = item.provenance.record?.referenceOrigin
    }

    /// The facts about an image in memory, which may not have reached the disk yet.
    public init(_ image: GeneratedImage, modelName: String? = nil, seedFormat: SeedFormat = .hex) {
        model = modelName ?? image.modelID
        size = Self.label(image.settings.size)
        steps = Self.stepsLabel(image.settings.steps)
        seed = Self.seedLabel(image.settings.seed, as: seedFormat)
        took = Self.tookLabel(seconds: image.duration.seconds, steps: image.settings.steps)
        file = image.fileURL?.lastPathComponent ?? Self.notSaved
        // A picture in memory has no record to read it from, and the library's own inspector
        // takes over the moment the scan lands, which is typically inside a second.
        upscaled = nil
        length = image.video.map { Self.lengthLabel(frames: $0.frameCount, rate: $0.frameRate) }
        let settings = image.settings
        referenceStrengthValue = settings.referenceImage == nil
            ? nil : Self.reportable(settings.referenceStrength)
        referenceStrength = referenceStrengthValue.map(Self.strengthLabel)
        referenceOrigin = settings.referenceImage == nil ? nil : settings.referenceOrigin
    }

    /// A strength worth showing: not one that was never recorded, and not the 1 that means the
    /// generation had no distance to travel from its picture.
    static func reportable(_ strength: Double?) -> Double? {
        guard let strength, strength != 1 else { return nil }
        return strength
    }

    /// The strength as the slider spells it, to two decimals.
    static func strengthLabel(_ strength: Double) -> String {
        strength.formatted(.number.precision(.fractionLength(2)))
    }

    /// "2.0 s, 49 frames at 24 fps": the seconds to one decimal, since a ladder of eight frames
    /// rarely lands on a whole second.
    static func lengthLabel(frames: Int, rate: Double) -> String {
        String(format: "%.1f s, %d frames at %.0f fps", Double(frames) / rate, frames, rate)
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

    /// How many steps ran. None at all is not a generation but an upscale of a picture Zephra
    /// did not make, and "0" would read as a number that was once true.
    static func stepsLabel(_ steps: Int?) -> String {
        guard let steps, steps > 0 else { return unknown }
        return String(steps)
    }

    /// The seed, for the same reason: no seed was drawn when no denoising loop ran.
    static func seedLabel(_ seed: UInt64?, as format: SeedFormat) -> String {
        guard let seed, seed > 0 else { return unknown }
        return format.label(seed)
    }

    /// A middle dot, the separator the rest of the interface uses between facts.
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
