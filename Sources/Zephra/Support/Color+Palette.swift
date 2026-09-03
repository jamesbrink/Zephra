import SwiftUI

/// Zephra's two colours, both defined as asset-catalog colour sets so light and dark come
/// for free. Everything else on screen is a system material or a system label colour, which
/// is what lets the picture behind the capsule do the tinting.
extension Color {
    /// The ground a picture sits on: graphite in the dark, warm paper in the light.
    nonisolated static let canvasBackground = Color("CanvasBackground", bundle: .main)

    /// Safelight amber, the one accent. Only ever shown while the model is working.
    nonisolated static let safelight = Color("Safelight", bundle: .main)

    /// The four muted colours a model's dot can take, in catalog order.
    ///
    /// They identify a model; they never mean anything. That is why they are a small closed
    /// set rather than a colour per model: four are told apart at a glance, twelve are not.
    private nonisolated static let modelDots = [
        Color("ModelDot1", bundle: .main),
        Color("ModelDot2", bundle: .main),
        Color("ModelDot3", bundle: .main),
        Color("ModelDot4", bundle: .main),
    ]

    /// The colour standing for one model, by descriptor identifier.
    ///
    /// Chosen by hashing the identifier rather than by its position in `ModelCatalog.all`, so a
    /// model keeps its colour when another is added above it. The hash is written out rather
    /// than taken from `hashValue`, which is salted per process and would hand the same model a
    /// different colour on every launch.
    nonisolated static func modelDot(_ id: String) -> Color {
        modelDots[Int(fnv1a(id) % UInt64(modelDots.count))]
    }

    /// FNV-1a over the identifier's UTF-8, 64-bit. Small, stable, and good enough to spread
    /// three or four names across four buckets.
    private nonisolated static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return hash
    }
}
