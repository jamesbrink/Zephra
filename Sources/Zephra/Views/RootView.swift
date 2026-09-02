import SwiftUI
import ZephraCore
import ZephraEngine

/// The window: canvas everywhere, one floating capsule over the bottom of it, the session's
/// images under that, and the engine's status as the window's subtitle.
struct RootView: View {
    @Environment(GenerationStore.self) private var store
    @AppStorage(AppSettings.lastPrompt) private var lastPrompt = ""
    @AppStorage(AppSettings.filmstripVisible) private var filmstripVisible = AppSettings.initialFilmstripVisible

    var body: some View {
        CanvasView()
            .overlay(alignment: .bottom) { controls }
            .toolbar { toolbarContent }
            .navigationTitle("Zephra")
            .navigationSubtitle(subtitle)
            .task {
                let saved = lastPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if store.settings.prompt.isEmpty, !saved.isEmpty {
                    store.settings.prompt = lastPrompt
                }
                await store.bootstrapFromInterface()
            }
            .onChange(of: store.settings.prompt) { _, prompt in
                // An empty field is a draft in progress, not a decision to forget the last prompt.
                guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                lastPrompt = prompt
            }
    }

    private var subtitle: String {
        let count = store.queue.count
        guard count > 0 else { return store.state.subtitle }
        return "\(store.state.subtitle) · \(count) queued"
    }

    private var controls: some View {
        VStack(spacing: 14) {
            caption
            PromptCapsule()
            if filmstripVisible { Filmstrip() }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: 736)
    }

    @ViewBuilder
    private var caption: some View {
        if let image = store.current, !store.state.isBusy,
           image.settings.prompt != store.settings.prompt {
            Text(image.settings.prompt)
                .font(.callout)
                .fontDesign(.serif)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .shadow(color: .black.opacity(0.55), radius: 6)
                .padding(.horizontal, 24)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            SizeMenu()
            Button {
                filmstripVisible.toggle()
            } label: {
                Label("Session images", systemImage: "film")
                    .symbolVariant(filmstripVisible ? .fill : .none)
            }
            .help("Show this session's images")
        }
    }
}

#Preview("Ready") {
    RootView()
        .frame(width: 1100, height: 760)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .ready))
}

#Preview("Downloading") {
    RootView()
        .frame(width: 1100, height: 760)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .downloading(
            DownloadProgressEvent(completedFiles: 3, totalFiles: 11, fraction: 0.34, bytesPerSecond: 46_000_000)
        )))
}

#Preview("Failed") {
    RootView()
        .frame(width: 1100, height: 760)
        .environment(ImageCache())
        .environment(GenerationStore.preview(state: .failed(.backend(.loadFailed("not enough free memory")))))
}
