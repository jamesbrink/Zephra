import Foundation
import ZephraCore

extension GenerationStore {
    /// The folder finished images are written to. The one answer to that question: nothing
    /// else works the path out for itself.
    public var outputDirectory: URL { library.root }

    /// True when a generation can start right now: the engine is ready and there is a prompt.
    public var canGenerate: Bool {
        !isChangingModelDirectory && !isChangingImageDirectory && !isShuttingDown && !deletionInProgress && state.acceptsGeneration && settings.isReadyToGenerate && !isAdoptingReference
    }

    /// True when `generate()` will do something: start now, or queue behind the running one.
    public var canQueue: Bool {
        !isChangingModelDirectory && !isChangingImageDirectory && !isShuttingDown && !deletionInProgress && settings.isReadyToGenerate && (state.acceptsGeneration || isDraining) && !isAdoptingReference
    }

    /// Shows an earlier image on the canvas and adopts its settings, so the obvious next move
    /// is to tweak one thing and generate a variation.
    public func select(_ image: GeneratedImage) {
        guard !isChangingImageDirectory else { return }
        stopFollowingRun()
        // The settings about to be adopted include the picture's own reference, or none; a
        // library read still on its way was for the settings being replaced.
        _ = claimReference()
        current = image
        settings = image.settings
        // Everything else carries over whichever model made it; a picture to edit does not,
        // on a model that cannot read one, or the well could neither show it nor clear it.
        if !descriptor.capabilities.supportsReferenceImage {
            settings.referenceImage = nil
        }
    }

    /// Picks a fresh seed for the next generation.
    public func randomizeSeed() { settings = settings.withRandomSeed() }

    /// Waits for everything this store has in flight. A seam for tests, which need generation
    /// and the file write that follows it to be finished before they assert.
    func settle() async {
        await stopTask?.value
        await switchTask?.value
        await bootstrapTask?.value
        await generationTask?.value
        // Before the save task: an upscale's write is queued on it as the upscale ends, and
        // this one is nil the moment that has happened.
        await upscaleTask?.value
        await saveTask?.value
        await libraryTask?.value
        await openTask?.value
    }
}
