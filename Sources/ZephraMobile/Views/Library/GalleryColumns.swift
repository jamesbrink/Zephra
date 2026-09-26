import SwiftUI

private struct GalleryColumnsKey: EnvironmentKey { static let defaultValue = 3 }
extension EnvironmentValues {
    var galleryColumns: Int {
        get { self[GalleryColumnsKey.self] }
        set { self[GalleryColumnsKey.self] = newValue }
    }
}
