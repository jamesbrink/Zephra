import Foundation
import ZephraCore

extension GenerationStore {
    /// The folder finished images are written to. The one answer to that question: nothing
    /// else works the path out for itself.
    public var outputDirectory: URL { library.root }

    /// True when a generation can start right now: the engine is ready and there is a prompt.
    public var canGenerate: Bool {
        acceptsWork && state.acceptsGeneration && settings.isReadyToGenerate
            && !isAdoptingReference
    }

    /// True when `generate()` will do something: start now, or queue behind the running one.
    public var canQueue: Bool {
        acceptsWork && settings.isReadyToGenerate && (state.acceptsGeneration || isDraining)
            && !isAdoptingReference
    }

    /// Shows an earlier image on the canvas and adopts its settings and its model, so the
    /// obvious next move is to tweak one thing and generate a variation — of the same picture,
    /// on the model that made it.
    ///
    /// The model is chosen, not loaded: `descriptor` moves so the menu and the capsule's
    /// controls say what Generate will run, and `modelAwaitsGenerate` keeps the weights where
    /// they are until it does. The settings are taken wholesale, since they were made on that
    /// model — not clamped, which would pin a strength of 1 that says "no picture" into the
    /// slider's range. A picture from a model this build no longer ships keeps the current
    /// model and takes its schedule, as a variation of one does; that is where a clamp is
    /// wanted, and it also drops a reference the current model cannot read.
    public func select(_ image: GeneratedImage) {
        guard !isChangingImageDirectory else { return }
        stopFollowingRun()
        // The settings about to be adopted include the picture's own reference, or none; a
        // library read still on its way was for the settings being replaced.
        _ = claimReference()
        current = image
        if let known = ModelCatalog.descriptor(id: image.modelID) {
            adoptForGenerate(known)
            settings = image.settings
        } else {
            settings = descriptor.capabilities.clamp(image.settings.onSchedule(of: descriptor))
        }
    }

    /// Makes `model` the one the next generation uses without loading it, and says so, unless
    /// it is the one in use already, in which case there is nothing to wait for.
    func adoptForGenerate(_ model: ModelDescriptor) {
        descriptor = model
        modelAwaitsGenerate = model.id != modelInUse?.id
    }

    /// The model whose weights are resident, or the one on its way in: a picture chosen while
    /// the launch's model is still warming up must wait for Generate as it would a moment
    /// later, and must not be the model remembered for the next launch either.
    var modelInUse: ModelDescriptor? { loadedDescriptor ?? preparingModel }

    /// The model the next launch should open on: the one chosen, unless the choice is only a
    /// picture's and is waiting for Generate, in which case the one in use — a picture looked
    /// at is not a model used.
    public var rememberedModel: ModelDescriptor {
        modelAwaitsGenerate ? (modelInUse ?? descriptor) : descriptor
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
