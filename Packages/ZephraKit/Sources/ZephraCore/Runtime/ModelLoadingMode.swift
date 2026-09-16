/// When a model's weights are read in: as soon as one is chosen, or only when asked for.
///
/// `.automatic` is what Zephra always did — the launch loads the chosen model, and a pick in the
/// menu swaps the weights behind it. `.onDemand` is the shape a person who runs several models
/// wants: choosing a model is choosing it, and the weights arrive when Load or Generate says so.
/// The engine's default stays `.automatic`, so a store nobody told behaves as it always has.
public enum ModelLoadingMode: String, Codable, Hashable, Sendable, CaseIterable {
    /// Choosing a model loads it, and the launch loads the one chosen last time.
    case automatic
    /// Nothing is loaded until Load or Generate asks for it.
    case onDemand
}
