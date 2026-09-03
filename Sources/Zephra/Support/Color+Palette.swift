import SwiftUI
import ZephraCore

/// Zephra's two colours, both defined as asset-catalog colour sets so light and dark come
/// for free. Everything else on screen is a system material or a system label colour, which
/// is what lets the picture behind the capsule do the tinting.
extension Color {
    /// The ground a picture sits on: graphite in the dark, warm paper in the light.
    nonisolated static let canvasBackground = Color("CanvasBackground", bundle: .main)

    /// Safelight amber, the one accent. Only ever shown while the model is working.
    nonisolated static let safelight = Color("Safelight", bundle: .main)

    /// The four muted colours a model's dot can take.
    ///
    /// They identify a model; they never mean anything, and none of them is safelight amber,
    /// which would say the model is working when it is only listed. Four rather than one per
    /// model because four are told apart at a glance and twelve are not.
    private nonisolated static let modelDots = [
        Color("ModelDot1", bundle: .main),
        Color("ModelDot2", bundle: .main),
        Color("ModelDot3", bundle: .main),
        Color("ModelDot4", bundle: .main),
    ]

    /// The colour standing for one model, by descriptor identifier.
    ///
    /// Taken from the model's place in `ModelCatalog.all`, so adjacent entries are always
    /// different colours — which a hash cannot promise, and did not: the two Z-Image builds
    /// landed in the same bucket. A new model appended to the catalog takes the next colour,
    /// and the four repeat from the fifth on. A model the catalog does not name falls to the
    /// first colour rather than to a crash.
    nonisolated static func modelDot(_ id: String) -> Color {
        let place = ModelCatalog.all.firstIndex { $0.id == id } ?? 0
        return modelDots[place % modelDots.count]
    }
}
