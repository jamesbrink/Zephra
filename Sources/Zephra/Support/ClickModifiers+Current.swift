import AppKit
import ZephraEngine

/// What is being held down right now, as the engine's own value.
///
/// The one place in the app that reads `NSEvent.modifierFlags`. SwiftUI's gestures do not
/// report modifiers on macOS, so a click has to ask the event system directly — and asking it
/// from every cell would be the same question in a dozen places, each free to answer it a
/// little differently.
extension LibraryCursor.ClickModifiers {
    /// The command and shift keys as they stand at this instant.
    static var current: LibraryCursor.ClickModifiers {
        let flags = NSEvent.modifierFlags
        var modifiers: LibraryCursor.ClickModifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        return modifiers
    }
}
