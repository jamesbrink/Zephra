import SwiftUI
import ZephraEngine

struct ModelDownloadRow: View {
    @Environment(GenerationStore.self) private var store
    let download: ModelDownload

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(download.model.fullName).font(.headline)
            Text(status).font(.caption).foregroundStyle(.secondary)
            if download.status == .downloading, let progress = download.progress {
                ProgressView(value: progress.fraction)
                if let done = progress.completedBytes, let total = progress.totalBytes {
                    Text("\(done.formatted(.byteCount(style: .file))) of \(total.formatted(.byteCount(style: .file)))")
                        .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            HStack {
                switch download.status {
                case .queued, .downloading:
                    Button("Pause") { store.pauseDownload(download.id) }.disabled(!canStop)
                    Button("Cancel download") { store.pauseDownload(download.id, discard: true) }.disabled(!canStop)
                case .paused:
                    Button("Resume") { store.resumeDownload(download.model) }
                        .disabled(store.isChangingModelDirectory || store.isStoppingPreparation || store.isShuttingDown)
                    Button("Cancel download") { store.pauseDownload(download.id, discard: true) }.disabled(!canStop)
                case .cancelled, .failed:
                    Button(download.status == .paused ? "Resume" : "Retry") { store.resumeDownload(download.model) }
                        .disabled(store.isChangingModelDirectory || store.isStoppingPreparation || store.isShuttingDown)
                case .completed: EmptyView()
                }
            }
            .controlSize(.small)
            if !canStop, download.status == .queued || download.status == .downloading {
                Text("In use by preparation or queued work. Use Stop on the canvas, or remove queued work first.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if (download.status == .paused || download.status == .cancelled), store.downloads.sharesActiveTransfer(download.model) {
                Text("The shared download continues for another model.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var canStop: Bool { store.canStopDownload(download.id) }

    private var status: String {
        switch download.status {
        case .queued: "Waiting for a download slot or shared files"
        case .downloading: "Downloading"
        case .paused: "Paused — partial files kept"
        case .cancelled: "Cancelled"
        case .completed: "Available on this Mac"
        case .failed(let reason): reason
        }
    }
}
