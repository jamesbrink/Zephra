import Foundation
import ZephraCore
import ZephraLinkProtocol

/// Putting the pictures back into a request that named them.
///
/// A picture never rides inside a request: it crosses as a blob and the request names it by id,
/// so this is the one place the bytes are put back, for the plain `enqueue` and for the strict
/// multi-host `submit` alike. Order is the whole of it — a model that reads several pictures
/// reads them in the order it was handed them — so the blobs are taken in the order the request
/// names, and a missing one is refused by position rather than quietly leaving a short strip.
extension CompanionSession {
    /// The pictures `ids` name, in that order, taken out of the held blobs.
    ///
    /// `settings` are the request's own, whose pictures arrived without their bytes: each keeps
    /// the library file name it was of, so a phone's edit records the picture it started from
    /// the way a Mac's does.
    func takeReferences(
        named ids: [UUID], for settings: GenerationSettings
    ) throws -> [ReferencePicture] {
        let pictures = try references(named: ids, for: settings)
        consumeBlobs(named: ids)
        return pictures
    }

    /// The same, for the strict path, with each blob checked against the input that declared it.
    ///
    /// Positionally: input `i` is the digest and the length of picture `i`, so a strip whose
    /// third picture is not what was offered is refused rather than run. A request naming more
    /// or fewer blobs than it declared inputs is refused for the same reason — the offer this
    /// submit was admitted on described a different piece of work. Nothing is consumed until
    /// every picture has matched, so a refusal leaves the phone's transfers where they were.
    func takeReferences(
        named ids: [UUID], matching inputs: [GenerationInput], for settings: GenerationSettings
    ) throws -> [ReferencePicture] {
        guard ids.count == inputs.count else {
            throw LinkError(
                code: .badRequest, reason: "This request's reference data does not match it.")
        }
        let pictures = try references(named: ids, for: settings)
        for (index, input) in inputs.enumerated() where !input.matches(pictures[index].data) {
            throw LinkError(
                code: .badRequest, reason: "Picture \(index + 1) does not match this request.")
        }
        consumeBlobs(named: ids)
        return pictures
    }

    /// The blobs read back as pictures, without taking them.
    private func references(
        named ids: [UUID], for settings: GenerationSettings
    ) throws -> [ReferencePicture] {
        guard !ids.isEmpty else { return [] }
        guard ids.count <= ReferenceLimits.maximumPictures else {
            throw LinkError(
                code: .badRequest,
                reason: "A generation may read at most \(ReferenceLimits.maximumPictures) pictures.")
        }
        return try ids.enumerated().map { index, id in
            guard let bytes = blobs[id] else {
                throw LinkError(
                    code: .notFound, reason: "Picture \(index + 1) for that request never arrived.")
            }
            let stripped = index < settings.referenceImages.count
                ? settings.referenceImages[index] : nil
            return ReferencePicture(
                data: bytes, origin: stripped?.origin, size: stripped?.size)
        }
    }

    /// Drops the blobs a request has now taken: a picture belongs to the run that named it.
    private func consumeBlobs(named ids: [UUID]) {
        for id in ids { blobs.removeValue(forKey: id) }
        blobOrder.removeAll { ids.contains($0) }
    }
}
