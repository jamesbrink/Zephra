import Foundation
import ZephraCore

/// The well as a strip: several pictures, in the order the model reads them.
///
/// A new concern in its own extension, the way every other one is. What is here is the list —
/// putting pictures in and taking one out; moving one along it is
/// `GenerationStore+ReferenceOrder` — and what is in `GenerationStore+Reference` is the ticket
/// and the doors that speak of one picture. Every change ends in
/// `settleAfterReferenceChange(previousFirst:)`, so the continuation, the strength and the size
/// follow one rule however the strip moved.
extension GenerationStore {
    /// How many more pictures the chosen model would read: none at all on a model that reads
    /// no picture, and none once the strip is as long as the model or the limits allow.
    public var referenceRoom: Int {
        let capabilities = descriptor.capabilities
        guard capabilities.supportsReferenceImage else { return 0 }
        let most = min(capabilities.referenceImageCount.upperBound, ReferenceLimits.maximumPictures)
        return max(0, most - settings.referenceImages.count)
    }

    /// Replaces the strip with `pictures`, on behalf of the choice numbered `ticket`.
    public func useAsReferences(_ pictures: [ReferencePicture], ticket: Int) {
        guard ticket == referenceChoice else { return }
        useAsReferences(pictures)
    }

    /// Replaces the strip with `pictures`, trimmed to what the model reads and to what the
    /// limits allow.
    public func useAsReferences(_ pictures: [ReferencePicture]) {
        let previous = settings.referenceImages.first
        settings.referenceImages = []
        take(pictures, previousFirst: previous)
    }

    /// Adds `pictures` to the end of the strip, on behalf of the choice numbered `ticket`.
    public func appendReferences(_ pictures: [ReferencePicture], ticket: Int) {
        guard ticket == referenceChoice else { return }
        appendReferences(pictures)
    }

    /// Adds `pictures` to the end of the strip, as far as there is room.
    public func appendReferences(_ pictures: [ReferencePicture]) {
        take(pictures, previousFirst: settings.referenceImages.first)
    }

    /// Adds one picture to the end of the strip, which is what a slot's own door hands over.
    public func appendReference(_ picture: ReferencePicture) {
        appendReferences([picture])
    }

    /// Empties the well, which takes the strength and the clip's tail with it.
    public func clearReferences() {
        let previous = settings.referenceImages.first
        referenceNote = nil
        settings.referenceImages = []
        settleAfterReferenceChange(previousFirst: previous)
    }

    /// Takes one picture out. An index the strip has not got changes nothing.
    public func removeReference(at index: Int) {
        guard settings.referenceImages.indices.contains(index) else { return }
        let previous = settings.referenceImages.first
        referenceNote = nil
        settings.referenceImages.remove(at: index)
        settleAfterReferenceChange(previousFirst: previous)
    }

    /// Puts another picture in one slot's place, on behalf of the choice numbered `ticket`.
    public func replaceReference(at index: Int, with picture: ReferencePicture, ticket: Int) {
        guard ticket == referenceChoice, settings.referenceImages.indices.contains(index) else {
            return
        }
        let previous = settings.referenceImages.first
        referenceNote = nil
        settings.referenceImages[index] = picture
        settleAfterReferenceChange(previousFirst: previous)
    }

    /// Runs `read` off the main actor and puts every picture it returns in, in order, unless a
    /// newer choice has been made in the meantime.
    ///
    /// One claim and one landing for a door that hands over several — a drop of five files, a
    /// picker's multiple selection — because five reads under five tickets would land only the
    /// last. Generate waits on it through `isAdoptingReference`, as it waits on one picture.
    public func adoptReferences(_ read: @escaping @Sendable () async -> [ReferencePicture]) {
        let ticket = claimReference()
        referenceRead = Task { [weak self] in
            let pictures = await Task.detached(priority: .userInitiated, operation: read).value
            guard let self, !Task.isCancelled else { return }
            defer { if referenceChoice == ticket { referenceRead = nil } }
            guard !pictures.isEmpty else { return }
            appendReferences(pictures, ticket: ticket)
        }
    }

    /// Takes as many of `pictures` as the model and the budget allow, and says so when it takes
    /// fewer. The note is what the interface shows; the log line is what `make logs` shows, the
    /// rule the memory guard already follows — a refusal nobody can read is a refusal nobody
    /// can act on.
    private func take(_ pictures: [ReferencePicture], previousFirst: ReferencePicture?) {
        guard descriptor.capabilities.supportsReferenceImage else {
            referenceNote = nil
            settleAfterReferenceChange(previousFirst: previousFirst)
            return
        }
        let room = referenceRoom
        let offered = pictures.filter(\.hasPixels)
        let wanted = Array(offered.prefix(room))
        let held = settings.referenceImages + wanted
        let kept = ReferenceLimits.withinBudget(held)
        settings.referenceImages = kept
        let taken = kept.count - (held.count - wanted.count)
        if taken < offered.count {
            referenceNote = Self.referenceRefusal(offered: offered.count, taken: max(taken, 0))
            logger.info(
                "reference well took \(max(taken, 0)) of \(offered.count) picture(s): \(self.referenceNote ?? "")"
            )
        } else {
            referenceNote = nil
            logger.info("reference well holds \(self.settings.referenceImages.count) picture(s)")
        }
        settleAfterReferenceChange(previousFirst: previousFirst)
    }

    /// One sentence about what would not fit, in the words the canvas shows.
    private static func referenceRefusal(offered: Int, taken: Int) -> String {
        taken == 0
            ? "This model has no room for another reference picture."
            : "Only \(taken) of \(offered) pictures fit as references."
    }
}
