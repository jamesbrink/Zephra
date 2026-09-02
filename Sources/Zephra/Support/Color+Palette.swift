import SwiftUI

/// Zephra's two colours, both defined as asset-catalog colour sets so light and dark come
/// for free. Everything else on screen is a system material or a system label colour, which
/// is what lets the picture behind the capsule do the tinting.
extension Color {
    /// The ground a picture sits on: graphite in the dark, warm paper in the light.
    nonisolated static let canvasBackground = Color("CanvasBackground", bundle: .main)

    /// Safelight amber, the one accent. Only ever shown while the model is working.
    nonisolated static let safelight = Color("Safelight", bundle: .main)
}
