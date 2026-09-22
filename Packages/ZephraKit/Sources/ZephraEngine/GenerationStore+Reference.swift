import Foundation
import ZephraCore

/// The pictures a generation works from, on models that read any, and which choice of them is
/// current.
///
/// Choosing is numbered because the bytes seldom arrive at once: a library picture is read and
/// re-encoded off the main actor, a drop's provider delivers when it likes. Every way of
/// choosing takes a number when it is made — a drop as it is accepted, before a byte has
/// arrived — and only the latest number is allowed to land, so a slow picture chosen earlier
/// cannot arrive after a quick one and take the well back. The numbers are this store's, not
/// the process's: a second store's choices are its own.
///
/// One ticket covers the **whole** well rather than one per slot: a drop of five files is one
/// choice and lands as one (`adoptReferences`), where five tickets would land only the last —
/// which is precisely the failure the ticket exists to prevent.
///
/// The list operations are in `GenerationStore+ReferenceStrip`; these are the doors that speak
/// of one picture, which is what every model but one reads and what every door but the strip's
/// own offers.
extension GenerationStore {
    /// The number a choice made right now gets, cancelling any read still in flight.
    public func claimReference() -> Int {
        referenceRead?.cancel()
        referenceRead = nil
        referenceChoice += 1
        return referenceChoice
    }

    /// Puts `pngData` in on behalf of the choice numbered `ticket`, unless a newer choice has
    /// been made since the number was taken. `origin` is the library file name it came out of,
    /// when it came from the library.
    public func useAsReference(_ pngData: Data?, ticket: Int, origin: String? = nil) {
        guard ticket == referenceChoice else { return }
        useAsReference(pngData, origin: origin)
    }

    /// The pixel size of the first picture in the well: what it was measured at when it was
    /// encoded, or read from its own header, and nil with an empty well. What the Size menu
    /// offers the picture's shape from.
    public var referencePictureSize: ImageSize? {
        guard let first = settings.referenceImages.first, first.hasPixels else { return nil }
        return first.size ?? PNGImageSize.read(from: first.data)
    }

    /// Whether a picture is still on its way into the well. Generate waits for it: a request
    /// snapshotted a moment before the read landed would carry the picture before, or none.
    public var isAdoptingReference: Bool { referenceRead != nil }

    /// Runs `read` off the main actor and puts what it returns in, unless a newer choice has
    /// been made in the meantime. Nil from the read leaves whatever was there alone. The read
    /// may await — a drop's provider delivers when it likes — and Generate waits on it either
    /// way, through `isAdoptingReference`.
    ///
    /// `origin` travels with the choice rather than with the bytes, because it is known when
    /// the choice is made — a library door knows the file it opened; a drop and a file chooser
    /// pass nil — and the read that follows knows only pixels.
    public func adoptReference(
        origin: String? = nil, _ read: @escaping @Sendable () async -> Data?
    ) {
        let ticket = claimReference()
        referenceRead = Task { [weak self] in
            let png = await Task.detached(priority: .userInitiated, operation: read).value
            guard let self, !Task.isCancelled else { return }
            defer { if referenceChoice == ticket { referenceRead = nil } }
            guard let png else { return }
            useAsReference(png, ticket: ticket, origin: origin)
        }
    }

    /// Puts a picture in, or empties the well with nil.
    ///
    /// The one way the interface hands over a single picture, so the capability check lives
    /// here and not in each of the menu items and drop targets that offer one: a model that
    /// cannot read a picture never holds one, and `clamp` would drop it on the way to the
    /// backend anyway.
    ///
    /// Where the model has **room** for another picture this adds one; where it has not — which
    /// is always, past the first, on a model that reads one — it replaces the whole strip. One
    /// rule, and on every model that came before this one it is what it has always been. "Use
    /// this as the reference" with ten already in can only honestly mean starting afresh with
    /// the one chosen.
    public func useAsReference(_ pngData: Data?, origin: String? = nil) {
        guard let pngData else {
            clearReferences()
            return
        }
        let picture = ReferencePicture(
            data: pngData, origin: origin, size: PNGImageSize.read(from: pngData))
        if referenceRoom > 0, !settings.referenceImages.isEmpty {
            appendReferences([picture])
        } else {
            useAsReferences([picture])
        }
    }

    /// The three rules every change to the well settles, whatever changed it.
    ///
    /// A clip's end rides with the picture in the well (`GenerationStore+Extend`), so any other
    /// picture, or none, is no longer that clip's end. An empty well puts the strength back to
    /// 1, so a text-to-image request says what it means again; a picture arriving settles the
    /// strength into the model's bounds, because the 1 a picture-less request carries is outside
    /// the range a model that starts from a picture will accept and a slider bound to it would
    /// open pinned past its own maximum. And on a model that makes clips the size follows the
    /// **first** picture — its own shape, at the pixel budget of the size in force — because a
    /// clip is the picture moving; a later picture in the strip changes nothing, and a picture
    /// model leaves the size alone, since its pictures are references for the image asked for
    /// rather than the image.
    func settleAfterReferenceChange(previousFirst: ReferencePicture?) {
        settings.continuation = nil
        let capabilities = descriptor.capabilities
        guard let first = settings.referenceImages.first else {
            settings.referenceStrength = 1
            return
        }
        let bounds = capabilities.referenceStrengthBounds
        if !bounds.contains(settings.referenceStrength) {
            settings.referenceStrength = capabilities.defaultReferenceStrength
        }
        guard first.data != previousFirst?.data, capabilities.producesVideo,
              let size = first.size ?? PNGImageSize.read(from: first.data),
              let frame = capabilities.size(
                matchingAspectOf: size, budget: settings.size.pixelCount)
        else { return }
        settings.size = frame
    }
}
