import Foundation
import ZephraCore
import ZephraLinkProtocol

/// The well as a strip: several pictures, in the order the model reads them.
///
/// The Mac's `GenerationStore+ReferenceStrip` in a phone's shape, and deliberately the same
/// shape: a door adds pictures, a tile takes one out, a drag moves one, and every change ends
/// with the size following the **first** picture the way `useAsReference` makes it. What the
/// budget refuses is a sentence somebody can read under Generate rather than a picture that
/// silently did not arrive.
extension PromptDraft {
    /// How many more pictures `capabilities` would read: none on a model that reads no picture,
    /// and none once the strip is as long as the model or `ReferenceLimits` allows.
    func referenceRoom(for capabilities: ModelCapabilities) -> Int {
        guard capabilities.supportsReferenceImage else { return 0 }
        let most = min(capabilities.referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
        return max(0, most - references.count)
    }

    /// The pictures to send beside a request, as the Mac being spoken to would read them.
    ///
    /// An older Mac's summary defaults to `1...1`, so a phone talking to one sends its **first**
    /// picture and no others: the Mac would refuse the rest and the phone would have paid for
    /// them over a relay first.
    func references(allowedBy summary: CapabilitiesSummary) -> [ReferencePicture] {
        let capabilities = summary.capabilities
        guard capabilities.supportsReferenceImage else { return [] }
        let room = min(capabilities.referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
        return ReferenceLimits.withinBudget(Array(references.filter(\.hasPixels).prefix(room)))
    }

    /// The first picture's bytes, or nil where the model would not read one. The older door,
    /// kept because a single-picture caller means exactly this.
    func reference(allowedBy summary: CapabilitiesSummary) -> Data? {
        references(allowedBy: summary).first?.data
    }

    /// Adds pictures to the end of the strip, as far as the model and the budget allow.
    ///
    /// The answer is whether anything was taken, which is what a door reports back to the
    /// intent it was acting on: a fetch that succeeded and then found no room is not a fetch
    /// that filled the well.
    @discardableResult
    func append(
        _ pictures: [ReferencePicture], fitting capabilities: ModelCapabilities
    ) -> Bool {
        take(pictures, onto: references, fitting: capabilities)
    }

    /// Replaces the whole strip with `pictures`, which is what one picture chosen afresh means.
    @discardableResult
    func replaceReferences(
        _ pictures: [ReferencePicture], fitting capabilities: ModelCapabilities
    ) -> Bool {
        take(pictures, onto: [], fitting: capabilities)
    }

    /// D7: a picture is added where there is room and replaces the strip where there is not.
    ///
    /// One sentence, degenerate-correct. On a model that reads one picture there is never room
    /// past the first, so it replaces — which is what "Use as Reference" has always done. On a
    /// model that reads ten, with ten in, "use this as the reference" can only honestly mean
    /// starting afresh with the one chosen.
    @discardableResult
    func useAsReferences(
        _ pictures: [ReferencePicture], fitting capabilities: ModelCapabilities
    ) -> Bool {
        referenceRoom(for: capabilities) > 0
            ? append(pictures, fitting: capabilities)
            : replaceReferences(pictures, fitting: capabilities)
    }

    /// Takes one picture into an empty well, which is the older single-picture door.
    func adopt(
        _ picture: ReferencePicture, origin: String?, fitting capabilities: ModelCapabilities
    ) {
        var picture = picture
        picture.origin = origin
        replaceReferences([picture], fitting: capabilities)
    }

    /// Empties the well. Where a picture came from is a fact about the picture, so it goes with
    /// it rather than outliving it.
    func clearReferences() {
        let previous = references.first
        setReferences([])
        settle(previousFirst: previous, fitting: nil)
        settings.referenceImages = []
    }

    /// The older name, which still means exactly this.
    func clearReference() { clearReferences() }

    /// Takes one picture out. An index the strip has not got changes nothing.
    func removeReference(at index: Int) {
        guard references.indices.contains(index) else { return }
        let previous = references.first
        var kept = references
        kept.remove(at: index)
        setReferences(kept)
        settle(previousFirst: previous, fitting: nil)
        if kept.isEmpty { settings.referenceImages = [] }
    }

    /// Moves pictures along the strip, in the shape a list's `onMove` hands it over. The order
    /// is the order the model reads them in, so it is a choice rather than a presentation.
    func moveReferences(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let strip = references
        guard !offsets.isEmpty, offsets.allSatisfy(strip.indices.contains),
            (0...strip.count).contains(destination)
        else { return }
        var kept = strip.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        kept.insert(
            contentsOf: offsets.map { strip[$0] },
            at: destination - offsets.filter { $0 < destination }.count)
        setReferences(kept, note: referenceNote)
    }

    /// Puts as many of `pictures` onto `held` as there is room for, and says so when it takes
    /// fewer than it was offered.
    private func take(
        _ pictures: [ReferencePicture], onto held: [ReferencePicture],
        fitting capabilities: ModelCapabilities
    ) -> Bool {
        let previous = references.first
        // A model that reads no picture still lets the well hold the one somebody chose: the
        // well is where a choice waits, and `references(allowedBy:)` is what decides that
        // nothing crosses. Moving to a model that does read one finds the picture still there.
        let most = capabilities.supportsReferenceImage
            ? min(capabilities.referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
            : 1
        let offered = pictures.filter(\.hasPixels)
        let wanted = Array(offered.prefix(max(0, most - held.count)))
        let kept = ReferenceLimits.withinBudget(held + wanted)
        let taken = max(0, kept.count - held.count)
        setReferences(kept, note: taken < offered.count
            ? Self.referenceRefusal(offered: offered.count, taken: taken) : nil)
        settle(previousFirst: previous, fitting: capabilities)
        return taken > 0
    }

    /// One sentence about what would not fit, in the words the capsule shows under Generate.
    private static func referenceRefusal(offered: Int, taken: Int) -> String {
        taken == 0
            ? "This model has no room for another reference picture."
            : "Only \(taken) of \(offered) pictures fit as references."
    }

    /// The size follows the **first** picture and no other, the way the Mac's `useAsReference`
    /// does: on a model that makes clips the frame becomes that picture's own shape at the pixel
    /// budget in force, since a clip is the picture moving; a model that makes pictures leaves
    /// the size alone. A strip whose first picture did not move changes nothing.
    private func settle(previousFirst: ReferencePicture?, fitting capabilities: ModelCapabilities?) {
        guard let capabilities, capabilities.producesVideo,
            let first = references.first, first != previousFirst, let size = first.size,
            let shape = capabilities.size(matchingAspectOf: size, budget: settings.size.pixelCount)
        else { return }
        settings.size = shape
    }
}
