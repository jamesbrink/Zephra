import Foundation
import ZephraCore

/// The picture a generation edits, on models that read one.
extension GenerationStore {
    /// Puts a picture in, or takes it out with nil.
    ///
    /// The one way the interface sets a reference, so the capability check lives here and not
    /// in each of the menu items and drop targets that offer one: a model that cannot read a
    /// picture never holds one, and `clamp` would drop it on the way to the backend anyway.
    public func useAsReference(_ pngData: Data?) {
        settings.referenceImage =
            descriptor.capabilities.supportsReferenceImage ? pngData : nil
    }
}
