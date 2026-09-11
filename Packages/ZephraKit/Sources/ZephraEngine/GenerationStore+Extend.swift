import Foundation
import ZephraCore

/// Carrying a finished clip on: the next generation starts where this clip ends and the result
/// is joined onto it.
///
/// The move a person means by "Extend Clip": keep this clip's prompt, hold its last frames as
/// the new clip's first, and join what comes out onto the end. Like Animate, nothing here loads
/// weights — the model is chosen the way a picture chosen from the sidebar chooses its model,
/// and Generate is what loads it. The clip's end rides in the well as the picture, so the
/// capsule shows what the next clip starts from and any other picture put there drops the
/// continuation (`useAsReference`).
extension GenerationStore {
    /// Whether extending a clip is something this build can offer at all: the store takes
    /// work, it can read a clip back and join clips, and some model in the catalog makes clips.
    public var canExtend: Bool { acceptsWork && clips != nil && ModelCatalog.animator() != nil }

    /// Whether `record`'s clip in particular can be carried on: the model that would do it
    /// draws the clip's size on its own grid, since the join needs both parts the same shape.
    public func canExtend(_ record: GenerationRecord) -> Bool {
        guard canExtend, record.isVideo, let model = ModelCatalog.continuer(for: record.modelID)
        else { return false }
        let size = ImageSize(width: record.width, height: record.height)
        return model.capabilities.fit(size) == size
    }

    /// Sets the next generation up to carry `source` on.
    ///
    /// The tail is read off the main actor under the reference ticket, as a picture is, so a
    /// slow read can never land on a later choice. Nothing moves until it lands: a clip that
    /// will not read leaves the model, the settings and the well as they were. Then the clip's
    /// own model is chosen without being loaded (or the animator, when the clip's model cannot
    /// hold a clip's end), the prompt and the size are the clip's, the length is the model's
    /// default, and the last frame goes in the well with the tail behind it.
    public func extend(_ source: ContinuationSource) {
        guard canExtend(source.record), let clips,
            let model = ModelCatalog.continuer(for: source.record.modelID)
        else { return }
        stopFollowingRun()
        let ticket = claimReference()
        let count = model.capabilities.defaultContinuationFrames
        referenceRead = Task { [weak self] in
            let frames = await Task.detached(priority: .userInitiated) {
                switch source.clip {
                case .file(let url): try? await clips.tail(of: url, frames: count)
                case .bytes(let mp4): try? await clips.tail(ofData: mp4, frames: count)
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            defer { if referenceChoice == ticket { referenceRead = nil } }
            guard let frames, let last = frames.last, ticket == referenceChoice else { return }
            if model.id != descriptor.id { adopt(model) }
            adoptForGenerate(model)
            settings.prompt = source.record.prompt
            settings.negativePrompt = source.record.negativePrompt
            settings.size = ImageSize(width: source.record.width, height: source.record.height)
            settings.frames = model.capabilities.defaultFrames
            settings.referenceStrength = model.capabilities.defaultReferenceStrength
            capsuleHoldsPicture = false
            useAsReference(last, ticket: ticket, origin: source.origin)
            // After the picture, which clears any continuation on its way in; the size is the
            // clip's own and `useAsReference` keeps it, since the picture is that shape.
            settings.continuation = ClipContinuation(
                frames: frames, origin: source.origin,
                sourceFrameCount: source.record.frameCount ?? 1)
            settings.size = ImageSize(width: source.record.width, height: source.record.height)
        }
    }
}
