import Foundation
import ZephraLinkProtocol
import ZephraCore

/// The one door every picture enters the reference well through.
///
/// The Mac has a type of this name for the same reason: a picture arrives from the camera
/// roll, from the Mac's library, and one day from a share sheet, and all three have to end up
/// as the same bytes with the same rules applied. It holds no state — the draft does — and it
/// encodes off the main actor, since a photo out of a phone's camera is twelve megapixels and
/// resizing one on the main actor is a frozen capsule somebody is watching.
enum ReferenceAdoption {
    /// Takes the library's "start from this one" — a file name and nothing else — and hands the
    /// bytes behind it to `fill`.
    ///
    /// The picture comes through `LibraryCatalog`, so it crosses the link once for both
    /// surfaces: the one the library already has on disk is the one the well gets, and the one
    /// the well fetches is the one the library draws next. The name goes on as the origin,
    /// which is `GenerationSettings.referenceOrigin` — the provenance the Mac records beside
    /// the run.
    ///
    /// The request is taken before anything is fetched, so a slow link cannot leave it to be
    /// acted on twice; a failed fetch leaves the old picture visible but blocks Generate until the
    /// request is resolved or explicitly cleared.
    static func take(
        _ intent: ReferenceIntent, from catalog: LibraryCatalog,
        fill: (ReferencePicture, String) -> Bool
    ) async {
        guard let name = intent.take() else { return }
        let revision = intent.revision
        await resolve(intent, revision: revision,
            load: { await catalog.picture(named: name, priority: .reference) },
            fill: { fill($0, name) })
    }

    static func resolve(_ intent: ReferenceIntent, revision: UUID,
                        load: () async -> Data?, fill: (ReferencePicture) -> Bool) async {
        guard revision == intent.revision else { return }
        guard let data = await load(),
              let picture = await Task.detached(operation: { ReferenceImageEncoder.picture(from: data) }).value else {
            intent.resolved(revision, success: false)
            return
        }
        guard revision == intent.revision else { return }
        intent.resolved(revision, success: fill(picture))
    }
}
