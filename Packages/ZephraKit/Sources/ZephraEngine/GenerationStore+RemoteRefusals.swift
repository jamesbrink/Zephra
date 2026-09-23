import Foundation
import ZephraCore

/// The sentences `remoteAdmission` answers a paired device with when it will not queue a
/// request: what is wrong with the request itself, and why the store is taking no work at all.
/// Each is a `badRequest` or a `busy` on the wire, and each is one sentence, because a second
/// wording of the same refusal would be a second answer.
extension GenerationStore {
    /// What is wrong with the request itself, or nil when nothing is.
    func badRequest(
        _ model: ModelDescriptor, _ settings: GenerationSettings?, _ count: Int
    ) -> String? {
        guard ModelCatalog.descriptor(id: model.id) != nil else {
            return "This Mac's Zephra does not know a model called \(model.id)."
        }
        guard (1...Self.batchLimit).contains(count) else {
            return "Ask for between 1 and \(Self.batchLimit) images at a time."
        }
        if let settings, !settings.isReadyToGenerate { return "Write a prompt first." }
        // The wire is not a place to trust a value's invariants: a phone reads the model's own
        // `referenceImageCount` out of its summary and should never send more, but a request
        // that does is one no wait makes runnable.
        if let settings, let refusal = Self.referenceRefusal(settings, model) { return refusal }
        // A model this Mac cannot hold is greyed on the phone too, and asking for one is a
        // request no wait will make runnable: it is the request that is wrong, not the moment.
        // After the prompt, so a phone with nothing typed hears about the prompt.
        if let shortfall = staticShortfall(for: model) { return shortfall.sentence }
        return nil
    }

    /// What is wrong with a request's pictures for the model it names, or nil when nothing is:
    /// more pictures than that model reads, or more than the record and the link can carry.
    ///
    /// One sentence each, and both are `badRequest`: a model that reads one picture will not
    /// come to read four in a moment.
    static func referenceRefusal(
        _ settings: GenerationSettings, _ model: ModelDescriptor
    ) -> String? {
        let count = settings.referenceImages.count
        guard count > 1 else { return nil }
        guard count <= ReferenceLimits.maximumPictures else {
            return "A generation may read at most \(ReferenceLimits.maximumPictures) pictures."
        }
        let most = model.capabilities.supportsReferenceImage
            ? model.capabilities.referenceImageCount.upperBound : 0
        guard count > most else { return nil }
        return most == 1
            ? "\(model.displayName) reads one reference picture."
            : "\(model.displayName) reads at most \(most) reference pictures."
    }

    /// Why the store is taking no new work at all, or nil when it is. The order is the order a
    /// person would want to hear them in: the two folder changes are over in a moment, a
    /// deletion may not be, and quitting is the end of it.
    var busyReason: String? {
        guard !acceptsWork else { return nil }
        // `remoteAdmission` answers a lost GPU before it asks this, and this is the other
        // reader of `acceptsWork`: without it a Mac whose GPU has gone would tell a phone it
        // was deleting model storage.
        if deviceLost { return BackendError.deviceLostSentence }
        if isShuttingDown { return "Zephra is quitting." }
        if isChangingModelDirectory { return "Zephra is changing its models folder." }
        if isChangingImageDirectory { return "Zephra is changing its images folder." }
        return "Zephra is deleting model storage."
    }
}
