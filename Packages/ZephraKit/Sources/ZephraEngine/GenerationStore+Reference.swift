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
    /// been made since the number was taken. `origin` is the library file name it came out of,
    /// when it came from the library.
    public func useAsReference(_ pngData: Data?, ticket: Int, origin: String? = nil) {
        guard ticket == referenceChoice else { return }
        useAsReference(pngData, origin: origin)
    }

    /// The pixel size of the picture in the well, read from its own header, or nil without one.
    /// What the Size menu offers the picture's shape from.
    public var referencePictureSize: ImageSize? {
        settings.referenceImage.flatMap(PNGImageSize.read)
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

    /// Puts a picture in, or takes it out with nil.
    ///
    /// The one way the interface sets a reference, so the capability check lives here and not
    /// in each of the menu items and drop targets that offer one: a model that cannot read a
    /// picture never holds one, and `clamp` would drop it on the way to the backend anyway.
    ///
    /// A picture arriving also settles the strength, because the 1 that a picture-less request
    /// carries is outside the range a model that starts from a picture will accept: a slider
    /// bound to it would open pinned past its own maximum. Taking the picture out puts the 1
    /// back, so a text-to-image request says what it means again, and takes the origin with
    /// it — where a picture came from is a fact about the picture.
    ///
    /// On a model that makes clips the size follows the picture: its own shape, at the pixel
    /// budget of the size in force (`size(matchingAspectOf:budget:)`). A clip is the picture
    /// moving, so opening a portrait photograph at a landscape default would crop or letterbox
    /// it before a frame was made; and it is done here rather than in `animate` so Use as
    /// Reference, a drop, the picker and the well's own doors all agree. A picture model leaves
    /// the size alone: its picture is a reference for the image asked for, not the image.
    public func useAsReference(_ pngData: Data?, origin: String? = nil) {
        let capabilities = descriptor.capabilities
        let picture = capabilities.supportsReferenceImage ? pngData : nil
        settings.referenceImage = picture
        guard let picture else {
            settings.referenceOrigin = nil
            settings.referenceStrength = 1
            return
        }
        settings.referenceOrigin = origin
        let bounds = capabilities.referenceStrengthBounds
        if !bounds.contains(settings.referenceStrength) {
            settings.referenceStrength = capabilities.defaultReferenceStrength
        }
        guard capabilities.producesVideo, let size = PNGImageSize.read(from: picture),
              let frame = capabilities.size(matchingAspectOf: size, budget: settings.size.pixelCount)
        else { return }
        settings.size = frame
    }
}
