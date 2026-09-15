import SwiftUI

/// What can be done to one picture, in the Mac's own order.
///
/// The one menu every picture on the phone wears: a cell in the grid, and the viewer's More
/// button over the same picture full size. The Mac's `LibraryItemMenu` is the model, minus
/// what a phone has no business doing — there is no Open in Canvas because a tap already does
/// that, no Reveal in Finder and no album. Upscaling runs on the source Mac.
///
/// Each item is its own small view, the way the Mac's are, so what a thing does is changed in
/// the file it is named after rather than in a menu around it — and so no one view here holds
/// more than the three stored properties the rules allow.
struct LibraryItemMenu: View {
    /// The picture the menu was opened over.
    let entry: CachedEntry

    var body: some View {
        GenerationActions(entry: entry)
        Divider()
        UpscaleActions(entry: entry)
        UseAsReferenceButton(entry: entry)
        Divider()
        FavouriteButton(entry: entry)
        TagButton(entry: entry)
        Divider()
        SaveToPhotosButton(entry: entry)
        ShareButton(entry: entry)
        Divider()
        DeleteButton(entry: entry)
    }
}
