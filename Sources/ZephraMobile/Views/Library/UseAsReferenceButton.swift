import SwiftUI

/// "Use as Reference": the next generation starts from this picture.
///
/// It puts the library **file name** on `ReferenceIntent` and nothing else. The Mac already
/// has the picture — it made it — so the phone is asking for a name to be used, not sending a
/// megabyte of PNG back to the machine it came from. The capsule reads the intent, fills its
/// well and takes it; see `ReferenceIntent`.
///
/// Offered whether or not the Mac is in reach: it changes nothing until Generate is pressed,
/// and pressing that is the capsule's gate to keep.
struct UseAsReferenceButton: View {
    /// The picture to start from.
    let entry: CachedEntry

    @Environment(ReferenceIntent.self) private var reference

    var body: some View {
        Button("Use as Reference", systemImage: "photo.badge.plus") {
            reference.use(entry.fileName)
        }
    }
}
