import Foundation
import ZephraCore

/// The two controls a person presses, and a paired device asks for: read this model in now, and
/// give it back. Split out of `GenerationStore+Loading.swift`, which keeps the load itself.
///
/// Under `.onDemand` these and a press of Generate are the only three ways weights reach memory.
extension GenerationStore {
    /// Loads the chosen model now. What the Load control presses, and the door a paired
    /// device's `Command.loadModel` comes in through. Under `.onDemand` this and a press of
    /// Generate are the only two ways weights reach memory.
    public func loadModel() {
        guard acceptsWork, !isDraining, !isUpscaling, !isStoppingPreparation,
            canLoad(descriptor)
        else {
            // A press that did nothing says so in `make logs`, with the gate that refused it,
            // the way a refused press of Generate does.
            logger.info(
                "load refused: work \(self.acceptsWork), draining \(self.isDraining), upscaling \(self.isUpscaling), stopping \(self.isStoppingPreparation), loadable \(self.canLoad(self.descriptor))"
            )
            return
        }
        logger.info("loading \(self.descriptor.id, privacy: .public) because it was asked for")
        // An explicit Load is the explicit choice a picture's adoption was waiting for, exactly
        // as a menu pick is and as Generate is.
        modelAwaitsGenerate = false
        // Ready over another model's weights is a swap, and only this explicit press makes one
        // from `.ready`: `startLoading` still refuses it, so a second `bootstrap()` — a window
        // reopened — never swaps under a picture's model waiting for Generate.
        if isSwapFromReady(to: descriptor) {
            reload(descriptor, thenDrain: false)
            return
        }
        startLoading(descriptor, asSwap: false)
    }

    /// Whether Unload would do anything: weights are in and nothing is moving them already.
    public var canUnload: Bool {
        guard acceptsWork, !isDraining, !isUpscaling, !isSwappingModel, !isStoppingPreparation,
            loadedDescriptor != nil
        else { return false }
        // Never during a load, which is `canUpscale`'s rule for the same reason.
        // `loadedDescriptor` can still name an *earlier* model while a fresh load runs — a
        // change of models folder makes `isResident` false over a live descriptor — and
        // releasing those weights under a `bootstrapTask` nobody cancelled would leave that
        // load republishing over a store that believes it unloaded.
        switch state {
        case .idle, .ready, .failed: return true
        default: return false
        }
    }

    /// Gives the weights and their disk lease back, leaving the chosen model chosen.
    public func unloadModel() {
        guard canUnload else {
            logger.info(
                "unload refused: state \(self.state.logName, privacy: .public), loaded \(self.loadedDescriptor != nil)"
            )
            return
        }
        logger.info("unloading \(self.loadedDescriptor?.id ?? "", privacy: .public)")
        // `isSwappingModel` is exactly the right flag: the state passes through `.idle` while
        // the weights go back, and nothing else may load meanwhile.
        isSwappingModel = true
        transition(to: .idle)
        // `transition` is where a loss the runtime latched outside any run is noticed, and this
        // unload may be what noticed it: `canUnload` was read a line above the latch closing.
        // `releaseModel` would then do nothing, so the flag must not be left raised over a task
        // that does nothing either — and nothing else may load anyway, admission being shut.
        guard !deviceLost else {
            isSwappingModel = false
            logger.info("unload abandoned: the GPU is lost for this launch")
            return
        }
        switchTask = Task {
            await self.releaseModel()
            // A swap asked for while this was settling owns the flag; only this unload gives
            // it up, the rule `reload` and `stopPreparation` both follow.
            if !Task.isCancelled { self.isSwappingModel = false }
            self.modelAwaitsGenerate = false
            self.transition(to: .idle)
        }
    }

    /// Loads `model` and waits for it, unless a load is already under way. `asSwap` marks the
    /// load a model swap makes for itself; nothing else may load while a swap is in flight.
    func load(_ model: ModelDescriptor, asSwap: Bool) async {
        guard let task = startLoading(model, asSwap: asSwap) else { return }
        await task.value
    }

    /// Starts the same work as `bootstrap` without waiting for it, for a button that only has
    /// to kick it off: the remedy after a failure, and the resume after a cancelled download.
    public func retry() {
        // Never over a lost GPU. `startLoading` refuses it anyway through `acceptsWork`, but a
        // retry is the one press people make twice in ten seconds and the reason it does
        // nothing belongs in the log rather than in a silent early return two files away.
        guard !deviceLost else {
            logger.info("retry refused: the GPU is lost for this launch")
            return
        }
        startLoading(descriptor, asSwap: false)
    }
}
