import Foundation
import ZephraCore
import ZephraLinkProtocol

/// The one door every picture enters the reference well through.
///
/// The Mac has a type of this name for the same reason: a picture arrives from the camera
/// roll, from the Mac's library, and one day from a share sheet, and all three have to end up
/// as the same bytes with the same rules applied. It holds no state — the draft does — and it
/// encodes off the main actor, since a photo out of a phone's camera is twelve megapixels and
/// resizing one on the main actor is a frozen capsule somebody is watching.
///
/// A door that hands over several pictures is **one** read and **one** landing, under one
/// revision. Five reads under five revisions would land only the last, which is the failure the
/// revision exists to prevent; and one landing is what lets the draft decide once whether there
/// is room for what it was offered.
enum ReferenceAdoption {
    /// Takes the library's "start from these" — file names and nothing else — and hands the
    /// pictures behind them to `fill`, in the order they were named.
    ///
    /// Each picture comes through `LibraryCatalog`, so it crosses the link once for both
    /// surfaces and one budget sees every one of them: the pictures the library already has on
    /// disk are the ones the well gets, and the ones the well fetches are the ones the library
    /// draws next. Each name goes on as that picture's `origin`, which is the provenance the
    /// Mac records beside the run.
    ///
    /// The request is taken before anything is fetched, so a slow link cannot leave it to be
    /// acted on twice; a failed fetch leaves the old pictures visible but blocks Generate until
    /// the request is resolved or explicitly cleared.
    static func take(
        _ intent: ReferenceIntent, from catalog: LibraryCatalog,
        fill: ([ReferencePicture]) -> Bool
    ) async {
        let names = intent.take()
        guard !names.isEmpty else { return }
        let revision = intent.revision
        await resolve(intent, revision: revision, load: {
            var pictures: [ReferencePicture] = []
            for name in names {
                guard let data = await catalog.picture(named: name, priority: .reference),
                    var picture = await encoded(data)
                else { continue }
                picture.origin = name
                pictures.append(picture)
            }
            return pictures
        }, fill: fill)
    }

    /// Runs one read under one revision and lands what it returns, unless a newer choice was
    /// made while it ran. Nothing read at all is a failure somebody is told about; anything read
    /// is offered to the draft, which answers whether it took it.
    static func resolve(
        _ intent: ReferenceIntent, revision: UUID,
        load: () async -> [ReferencePicture], fill: ([ReferencePicture]) -> Bool
    ) async {
        guard revision == intent.revision else { return }
        let pictures = await load()
        guard !pictures.isEmpty else {
            intent.resolved(revision, success: false)
            return
        }
        guard revision == intent.revision else { return }
        intent.resolved(revision, success: fill(pictures))
    }

    /// One picture's bytes as a reference, resized off the main actor.
    static func encoded(_ data: Data) async -> ReferencePicture? {
        await Task.detached(operation: { ReferenceImageEncoder.picture(from: data) }).value
    }
}
