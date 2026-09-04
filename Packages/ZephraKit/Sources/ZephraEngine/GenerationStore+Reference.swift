import Foundation
import ZephraCore

/// The picture a generation edits, on models that read one, and which choice of it is current.
///
/// Choosing is numbered because the bytes seldom arrive at once: a library picture is read and
/// re-encoded off the main actor, a drop's provider delivers when it likes. Every way of
/// choosing takes a number when it is made — a drop as it is accepted, before a byte has
/// arrived — and only the latest number is allowed to land, so a slow picture chosen earlier
/// cannot arrive after a quick one and take the well back. The numbers are this store's, not
/// the process's: a second store's choices are its own.
extension GenerationStore {
    /// The number a choice made right now gets, cancelling any read still in flight.
    public func claimReference() -> Int {
        referenceRead?.cancel()
        referenceRead = nil
        referenceChoice += 1
        return referenceChoice
    }

    /// Puts `pngData` in on behalf of the choice numbered `ticket`, unless a newer choice has
    /// been made since the number was taken.
    public func useAsReference(_ pngData: Data?, ticket: Int) {
        guard ticket == referenceChoice else { return }
        useAsReference(pngData)
    }

    /// Whether a picture is still on its way into the well. Generate waits for it: a request
    /// snapshotted a moment before the read landed would carry the picture before, or none.
    public var isAdoptingReference: Bool { referenceRead != nil }

    /// Runs `read` off the main actor and puts what it returns in, unless a newer choice has
    /// been made in the meantime. Nil from the read leaves whatever was there alone.
    public func adoptReference(_ read: @escaping @Sendable () -> Data?) {
        let ticket = claimReference()
        referenceRead = Task { [weak self] in
            let png = await Task.detached(priority: .userInitiated, operation: read).value
            guard let self, !Task.isCancelled else { return }
            defer { if referenceChoice == ticket { referenceRead = nil } }
            guard let png else { return }
            useAsReference(png, ticket: ticket)
        }
    }

    /// Puts a picture in, or takes it out with nil.
    ///
    /// The one way the interface sets a reference, so the capability check lives here and not
    /// in each of the menu items and drop targets that offer one: a model that cannot read a
    /// picture never holds one, and `clamp` would drop it on the way to the backend anyway.
    ///
    /// A picture arriving also settles the strength, because the 1 that a picture-less request
    /// carries is outside the range a model that starts from a picture will accept: a slider
    /// bound to it would open pinned past its own maximum. Taking the picture out puts the 1
    /// back, so a text-to-image request says what it means again.
    public func useAsReference(_ pngData: Data?) {
        let capabilities = descriptor.capabilities
        let picture = capabilities.supportsReferenceImage ? pngData : nil
        settings.referenceImage = picture
        guard picture != nil else {
            settings.referenceStrength = 1
            return
        }
        let bounds = capabilities.referenceStrengthBounds
        if !bounds.contains(settings.referenceStrength) {
            settings.referenceStrength = capabilities.defaultReferenceStrength
        }
    }
}
