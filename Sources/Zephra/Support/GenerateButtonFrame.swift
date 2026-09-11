import SwiftUI

/// Where the Generate button is, in the hosting view's coordinate space, for
/// `GenerateClickTests` to send a real click to it through a window.
///
/// A preference rather than a lookup: SwiftUI's own controls are not views AppKit can find,
/// and its accessibility tree stays empty in-process until an assistive client asks for it, so
/// the button says where it is and the test listens. Nothing in the app reads it.
struct GenerateButtonFrame: PreferenceKey {
    static let defaultValue: CGRect? = nil

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = nextValue() ?? value
    }
}
