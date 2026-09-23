import Foundation

/// The one picture most of Zephra reads, over the list every request really carries.
///
/// `referenceImages` is the stored truth and these two name its first entry, permanently rather
/// than as a migration: five of the six families, the bench, the record's flat fields and most of
/// the interface read one picture, and there is nothing for them to learn from a list. It is how
/// `frames` and `continuation` were added, and it is what keeps a one-picture request byte for
/// byte what it was.
extension GenerationSettings {
    /// The first picture's bytes, as PNG, or nil where there is none — which is what a model
    /// that reads one picture asks for, and what every door into the well sets.
    ///
    /// Setting it replaces the whole list with that one picture, and nil empties it, which is
    /// `useAsReference`'s meaning exactly. A picture whose bytes were stripped for the wire
    /// reads as nil, since bytes are what this names.
    public var referenceImage: Data? {
        get {
            guard let first = referenceImages.first, first.hasPixels else { return nil }
            return first.data
        }
        set {
            guard let newValue else {
                referenceImages = []
                return
            }
            referenceImages = [ReferencePicture(data: newValue)]
        }
    }

    /// The first picture's `origin` — the library file name it came out of, when it came from
    /// the library, and nil when it came from a file chooser or a drop.
    ///
    /// Setting it writes that picture's origin, and is a no-op on an empty list: where a picture
    /// came from is only ever a fact about the picture, so an origin with no picture would be a
    /// request claiming provenance it has not got.
    public var referenceOrigin: String? {
        get { referenceImages.first?.origin }
        set {
            guard !referenceImages.isEmpty else { return }
            referenceImages[0].origin = newValue
        }
    }
}
