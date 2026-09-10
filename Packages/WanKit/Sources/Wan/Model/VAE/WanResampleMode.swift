import Foundation

/// How a `WanResample` changes a clip's size, in the reference's four words.
///
/// Every mode halves or doubles height and width; the `3d` modes also halve or double time
/// with a causal convolution of their own, which is what a checkpoint's `time_conv` belongs to.
enum WanResampleMode: Hashable, Sendable {
    case upsample2d
    case upsample3d
    case downsample2d
    case downsample3d

    /// Whether the clip grows rather than shrinks.
    var upsamples: Bool {
        switch self {
        case .upsample2d, .upsample3d: true
        case .downsample2d, .downsample3d: false
        }
    }

    /// Whether time changes along with space.
    var resamplesTime: Bool {
        switch self {
        case .upsample3d, .downsample3d: true
        case .upsample2d, .downsample2d: false
        }
    }
}
