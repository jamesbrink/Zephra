import SwiftUI
import ZephraCore
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

#Preview("Three done, one to come") {
    let run = PreviewImages.run(of: 3)
    RunStrip()
        .padding()
        .frame(width: 620)
        .background(Color.canvasBackground)
        .environment(ImageCache())
        .environment(WorkspaceSelection(pane: .canvas))
        .environment(GenerationStore.preview(
            state: .generating(GenerationProgressEvent(
                phase: .denoising(step: 3, of: 4),
                fraction: 0.75
            )),
            images: run,
            running: QueuedGeneration(
                model: ModelCatalog.default,
                settings: run[0].settings,
                batchID: run[0].batchID ?? UUID(),
                batchIndex: 3
            )
        ))
}
