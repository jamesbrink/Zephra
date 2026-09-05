/// Where a model's weights live while it generates.
public enum WeightResidency: String, Hashable, Sendable {
    /// Every weight is read once at load and stays in memory: the fast path, and the only one
    /// on a Mac that can hold the model.
    case resident
    /// The transformer's blocks are read from the disk again on every step, a few at a time,
    /// so a model larger than the GPU's working set still runs. Each step costs one read of
    /// the model, hidden under the step's own compute on a slow GPU and not on a fast one.
    case streamed
}
