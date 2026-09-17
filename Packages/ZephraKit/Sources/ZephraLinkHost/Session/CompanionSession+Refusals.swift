import Foundation
import ZephraCore
import ZephraEngine
import ZephraLinkProtocol

/// The words a command is turned away with, in one place.
///
/// Pure and static: each of these is a question about the request and the Mac's own state, and
/// none of them touches the session. Together they are the whole vocabulary a phone hears when
/// an ask does not happen, and keeping them here is what stops one fact — a model this Mac
/// cannot hold — being answered with two different codes in two different commands.
extension CompanionSession {
    /// The catalog entry a command names, or a refusal the phone can show.
    static func model(_ id: String) throws -> ModelDescriptor {
        guard let model = ModelCatalog.descriptor(id: id) else {
            throw LinkError(
                code: .notFound, reason: "This Mac's Zephra does not know a model called \(id).")
        }
        return model
    }

    /// Why this Mac cannot hold `model`, or nil when it can — held whole, with the decode tiled,
    /// or read from disk every step.
    ///
    /// `badRequest` rather than `busy` or `refused`, which is the code `remoteAdmission` gives a
    /// generation on the same model: this is the machine rather than the moment, so asking again
    /// in a while is worth nothing. The sentence is `MemoryFit`'s own, so the greyed row on the
    /// phone and the refusal behind it say the same thing.
    static func unholdable(_ model: ModelDescriptor, on host: CompanionHost) -> LinkError? {
        let budget = host.store.memoryBudget
        let fit = ModelCatalog.fit(model, budget: budget)
        guard !fit.isSelectable else { return nil }
        return LinkError(code: .badRequest, reason: fit.reason(for: model, budget: budget))
    }

    /// Whether this command would put the device to work, which is what a Mac that has lost
    /// the GPU cannot take. Browsing the library, reading a picture and a resync all still
    /// work: the folder is a folder whatever the GPU is doing.
    static func needsTheGPU(_ command: Command) -> Bool {
        switch command {
        case .enqueue, .loadModel, .unloadModel, .switchModel, .upscale, .animate: true
        case .multiHost(let inner): needsTheGPU(inner)
        default: false
        }
    }

    /// The two multi-host commands that put work on the device are the strict offer and the
    /// strict submit; the rest — pausing previews, cancelling a run, reading a receipt back,
    /// listing the library — answer over a lost GPU like everything else that only reads. The
    /// submit matters most: it writes its `.prepared` receipt before the store ever sees the
    /// work, so refusing below that line, where `strictRefusal` and `enqueue` are the only
    /// doors, would leave the phone holding a receipt frozen at `unknown` beside the plain
    /// refusal it was told — one work named two ways.
    private static func needsTheGPU(_ command: MultiHostCommand) -> Bool {
        switch command {
        case .offer, .submit: true
        case .previews, .cancelRun, .receipt, .listing: false
        }
    }

    /// One admission answer as the refusal it is, or nil when the request was admitted.
    ///
    /// The three ways a request can fail are three different words on a phone, and the
    /// distinction is also what says whether asking again in a moment is worth anything.
    static func refusal(_ admission: RemoteAdmission) -> LinkError? {
        switch admission {
        case .admitted: nil
        case .busy(let reason): LinkError(code: .busy, reason: reason)
        case .refused(let reason): LinkError(code: .refused, reason: reason)
        case .badRequest(let reason): LinkError(code: .badRequest, reason: reason)
        }
    }
}
