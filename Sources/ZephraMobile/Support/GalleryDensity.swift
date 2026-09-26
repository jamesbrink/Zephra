import Foundation

/// Discrete Photos-style sizes; pinch out makes pictures larger, pinch in adds columns.
enum GalleryDensity {
    static func columns(start: Int, magnification: Double) -> Int {
        guard magnification.isFinite, magnification > 0 else { return min(6, max(1, start)) }
        return min(6, max(1, Int((Double(start) / magnification).rounded())))
    }
}
