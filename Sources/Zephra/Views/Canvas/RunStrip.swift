import SwiftUI
import ZephraEngine

/// This run's seeds under the capsule: what has come out so far, then a dashed square for each
/// one still to come.
///
/// It replaces the filmstrip of the last twenty-four images, which competed with the picture
/// for attention and answered a question the sidebar answers better. What belongs here is the
/// four variations you are choosing between right now.
struct RunStrip: View {
    @Environment(GenerationStore.self) private var store

    var body: some View {
        let batch = store.currentBatch
        let pending = store.pendingInCurrentBatch
        if !batch.isEmpty || pending > 0 {
            VStack(spacing: 6) {
                RunStripHeader(seeds: batch.count + pending)
                HStack(spacing: 8) {
                    ForEach(batch) { image in
                        FilmstripThumbnail(image: image)
                    }
                    ForEach(0..<pending, id: \.self) { _ in
                        PendingThumbnail()
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}
