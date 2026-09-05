import ZephraCore

/// Whether the VAE decode runs in tiles, decided for the model that is about to run.
///
/// The tile is a variable of the decode rather than of the loaded model, and the model that
/// runs is the job's own: a switch made mid-run moves `descriptor` while the running
/// generation finishes on the old model. So nothing here follows `descriptor`; the actor sets
/// the tile on its own queue at the start of each run, from the run's model.
extension GenerationStore {
    /// Adopts `policy` for every decode from now on. Nothing reloads: the next run simply
    /// reads the new answer.
    public func setVAETilingPolicy(_ policy: VAETilingPolicy) {
        vaeTilingPolicy = policy
    }

    /// The tile for a run about to start on `model`, or nil for the exact untiled decode.
    func vaeTile(for model: ModelDescriptor) -> Int? {
        vaeTilingPolicy.tileSize(for: model)
    }
}
