import ZephraCore

/// What a settings value may carry over the wire: everything but its pictures.
///
/// Megabytes of PNG inside a JSON envelope would block the channel for everything else, so
/// nothing that crosses the link holds pixels inside a `GenerationSettings`. A reference
/// picture crosses as a blob (`GenerationRequest.referenceBlobID`) and a clip's tail does not
/// cross at all: the phone has no pixels for the Mac's well, and the Mac's `clamp` drops a
/// continuation with no frames rather than running one. Both `GenerationRequest` and
/// `QueuedEntry` strip through here, so there is one rule about what a settings value on the
/// wire looks like.
extension GenerationSettings {
    /// The same settings with every reference picture's bytes dropped and the continuation kept
    /// without its frames, the way a finished image's record keeps it.
    ///
    /// The pictures themselves stay, emptied: what they were of — the library file name each
    /// came out of — is provenance rather than pixels, and a queue row on a phone has always
    /// said which picture a run started from. It is also what keeps the count honest, so a Mac
    /// can refuse a request naming more pictures than its model reads before a byte is put back.
    public func withoutPixels() -> GenerationSettings {
        var stripped = self
        stripped.referenceImages = referenceImages.map { $0.withoutPixels() }
        stripped.continuation = continuation?.withoutPixels()
        return stripped
    }
}
