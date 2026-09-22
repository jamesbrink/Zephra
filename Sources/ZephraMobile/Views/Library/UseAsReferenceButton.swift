import SwiftUI

/// "Use as Reference": the next generation starts from this picture.
///
/// It puts the library **file name** on `ReferenceIntent` and moves to the canvas. The Mac
/// already has the picture — it made it — so the phone is asking for a name to be used, not
/// sending a megabyte of PNG back to the machine it came from. The canvas reads the intent,
/// fetches the picture through the cache and fills its well; see `ReferenceIntentReader`.
///
/// The move is here rather than at the far end because it is one gesture: somebody who says
/// "start from this one" is asking to be taken to where a run is started. The intent survives
/// the move either way, which is what it is an object for.
///
/// What it does at the far end is D7's one rule, and the draft is where that rule lives: the
/// picture is added where there is room and replaces the whole strip where there is not. The
/// word on the button is `UseAsReferenceLabel`'s, which reads the same answer, so a button that
/// says "Add" cannot be a press that replaces.
///
/// Offered whether or not the Mac is in reach: it changes nothing until Generate is pressed,
/// and pressing that is the capsule's gate to keep.
struct UseAsReferenceButton: View {
    /// The picture to start from.
    let entry: CachedEntry

    @Environment(ReferenceIntent.self) private var reference
    @Environment(MobileSelection.self) private var selection

    var body: some View {
        Button {
            reference.use(entry.id)
            selection.tab = .canvas
        } label: {
            UseAsReferenceLabel()
        }
    }
}
