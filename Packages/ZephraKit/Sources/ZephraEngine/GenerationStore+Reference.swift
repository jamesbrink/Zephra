import Foundation
import ZephraCore

/// The picture a generation edits, on models that read one.
extension GenerationStore {
    /// Puts a picture in, or takes it out with nil.
    ///
    /// The one way the interface sets a reference, so the capability check lives here and not
    /// in each of the menu items and drop targets that offer one: a model that cannot read a
    /// picture never holds one, and `clamp` would drop it on the way to the backend anyway.
    ///
    /// A picture arriving also settles the strength, because the 1 that a picture-less request
    /// carries is outside the range a model that starts from a picture will accept: a slider
    /// bound to it would open pinned past its own maximum. Taking the picture out puts the 1
    /// back, so a text-to-image request says what it means again.
    public func useAsReference(_ pngData: Data?) {
        let capabilities = descriptor.capabilities
        let picture = capabilities.supportsReferenceImage ? pngData : nil
        settings.referenceImage = picture
        guard picture != nil else {
            settings.referenceStrength = 1
            return
        }
        let bounds = capabilities.referenceStrengthBounds
        if !bounds.contains(settings.referenceStrength) {
            settings.referenceStrength = capabilities.defaultReferenceStrength
        }
    }
}
