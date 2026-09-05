/// What the user asked for about streaming weights from disk.
///
/// The trade the setting makes: streaming lets a model larger than the GPU's working set run at
/// all, and costs one read of the model per step. Resident is the default wherever a Mac has
/// the memory for it, which is what `automatic` works out.
public enum WeightResidencyMode: String, CaseIterable, Hashable, Sendable {
    /// Stream only when the chosen model would otherwise page on this Mac, and only if it can.
    case automatic
    /// Always stream a model that can be streamed, whatever the machine.
    case always
    /// Never stream: the weights stay resident, even where that means swapping.
    case never

    /// How the setting reads in a picker.
    public var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .always: "Always"
        case .never: "Never"
        }
    }
}
