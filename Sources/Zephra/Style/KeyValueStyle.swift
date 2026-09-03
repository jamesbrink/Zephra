import SwiftUI

/// How the right-hand half of a `KeyValueRow` is set.
enum KeyValueStyle {
    /// Prose: a model name, a file name.
    case plain
    /// A fixed-width face, for a value read character by character, like a seed.
    case monospaced
    /// Proportional text with figures of one width, for a measurement that changes in place.
    case digits
}
