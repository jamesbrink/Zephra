import Foundation
import ZephraCore

/// Making a picture the first frame of a clip.
///
/// The move a person means by "Animate": keep the prompt they are working on, take this
/// picture, and set the next generation up on whichever model makes clips from one. Nothing
/// here loads weights — the model is chosen the way a picture chosen from the sidebar chooses
/// its model, and Generate is what loads it.
extension GenerationStore {
    /// Whether animating a picture is something this build can offer at all: the store takes
    /// work, and some model in the catalog makes clips from a picture.
    ///
    /// `acceptsWork` is the whole of the first half, so a folder being changed or storage being
    /// deleted greys the button along with everything else.
    public var canAnimate: Bool { acceptsWork && ModelCatalog.animator() != nil }

    /// Sets the next generation up to animate the picture `read` returns.
    ///
    /// A closure rather than bytes, for the reason `adoptReference` takes one: a library
    /// picture is read and re-encoded off the main actor, and a read started before the choice
    /// was numbered could land after a later choice and take the well back. The number is taken
    /// here, before anything is read; `origin` is the library file name the picture came out
    /// of, or nil for a file chooser pick or a drop.
    ///
    /// The prompt is kept. Animating *this* picture with *their* prompt is what the person
    /// asked for; replacing the prompt with the picture's own is what a variation is, and this
    /// is not that.
    public func animate(origin: String?, read: @escaping @Sendable () async -> Data?) {
        guard canAnimate, let model = ModelCatalog.animator() else { return }
        animate(with: model, origin: origin, read: read)
    }

    /// The rule itself, over whichever model is doing the animating. Separate from the catalog
    /// lookup so it can be driven with a model this build does not ship.
    func animate(
        with model: ModelDescriptor, origin: String?, read: @escaping @Sendable () async -> Data?
    ) {
        stopFollowingRun()
        // Chosen, not loaded, exactly as a picture picked off the sidebar chooses its model:
        // `adopt` moves the settings onto the new model's schedule, `adoptForGenerate` leaves
        // the weights where they are until Generate asks for these ones.
        if model.id != descriptor.id { adopt(model) }
        adoptForGenerate(model)
        settings.frames = model.capabilities.defaultFrames
        // The capsule is the user's again, not a picture's: the running card must not put a
        // run's settings back over the clip being set up. (Writing to `settings` says so too;
        // this says it on purpose rather than by side effect.)
        capsuleHoldsPicture = false
        // Takes the ticket now. The size follows the picture when it lands, in
        // `useAsReference`, which every other door into the well goes through as well.
        adoptReference(origin: origin, read)
    }
}
