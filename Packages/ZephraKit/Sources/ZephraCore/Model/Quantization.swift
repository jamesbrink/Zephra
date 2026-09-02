/// The numeric precision the weights were compressed to, trading image fidelity for memory.
public enum Quantization: String, Sendable, Codable, CaseIterable {
    /// Full brain-float precision, the largest and most faithful variant.
    case bf16
    /// Eight-bit weights, roughly half the memory of `bf16`.
    case int8
    /// Four-bit weights, the smallest variant and the most lossy.
    case int4

    /// How the precision is written in the interface, where "bit" reads better than the raw name.
    public var displayName: String {
        switch self {
        case .bf16: "bf16"
        case .int8: "8-bit"
        case .int4: "4-bit"
        }
    }
}
