import Foundation

/// How hard one component's linear weights are squeezed: the bits each weight keeps, and how
/// many weights share one scale and bias.
///
/// Smaller groups cost more memory — one float32 scale and one float32 bias per group — but
/// track the original values more closely, so the pair is the whole quality/size trade-off.
public struct QuantizationPrecision: Hashable, Sendable {
    /// The bit widths MLX can pack a weight into.
    public static let supportedBits: Set<Int> = [4, 8]
    /// The group sizes MLX's quantized matmul kernels accept.
    public static let supportedGroupSizes: Set<Int> = [32, 64, 128]

    /// Bits kept per weight.
    public let bits: Int
    /// Weights sharing one scale and bias.
    public let groupSize: Int

    /// Creates a precision, rejecting anything MLX's kernels cannot run.
    public init(bits: Int, groupSize: Int) throws {
        guard Self.supportedBits.contains(bits) else {
            throw QuantizationError.unsupportedBits(bits)
        }
        guard Self.supportedGroupSizes.contains(groupSize) else {
            throw QuantizationError.unsupportedGroupSize(groupSize)
        }
        self.bits = bits
        self.groupSize = groupSize
    }

    /// The effective cost of one weight on disk and in memory, counting the float32 scale and
    /// bias each group carries. Useful for predicting a variant's size before building it.
    public var bitsPerWeight: Double {
        Double(bits) + 64 / Double(groupSize)
    }

    /// How the pair reads in a log line or a manifest note.
    public var summary: String {
        "\(bits)-bit, group \(groupSize)"
    }
}
