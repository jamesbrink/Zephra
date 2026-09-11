import SwiftUI
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The chooser's answer: how the selected model would run here, and the two ways out.
///
/// The primary button names the model and what it will transfer, because pressing it is the
/// moment gigabytes start moving and that is the one place a person can still say no. Skipping
/// is a real answer too — the canvas then says the model is not loaded, and offers the chooser
/// again — so it is a button rather than a way of closing a window.
struct WelcomeFooter: View {
    @Environment(GenerationStore.self) private var store
    @Environment(WelcomeGate.self) private var welcome

    /// The selected model.
    let choice: ModelChoice

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(choice.reason)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 12)
            Button("Skip for Now") { welcome.dismiss() }
                .help("Go to the canvas without downloading a model")
            Button(action: choose) { Text(title) }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isObtainable)
                .help(store.availability[choice.model.id]?.reason ?? choice.reason)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
    }

    /// Records the answer, then loads the model. In that order: the workspace has to be up for
    /// the download it starts to have somewhere to report itself.
    private func choose() {
        welcome.dismiss()
        store.chooseFirstModel(choice.model)
    }

    /// What pressing it does, in its own words. Title Case, as a push button is.
    private var title: String {
        let name = choice.model.fullName
        switch store.availability[choice.model.id] {
        case .available: return "Continue with \(name)"
        case .needsBuild: return "Build \(name)"
        case .needsDownload(let bytes), .needsDownloadAndBuild(let bytes):
            return "Download \(name) \u{00B7} \(ByteCount.gigabytes(bytes))"
        // Nothing in the shipped catalog is `.missing`; the button is out for it either way,
        // and a disabled button offering a download it cannot start would be the worse label.
        case .missing: return "\(name) Isn't Available"
        case nil: return "Download \(name)"
        }
    }

    /// A model that cannot be had at all — a local build that was never made — is not offered
    /// as something to press. Nothing in the shipped catalog answers this way; it is here
    /// because a button that starts nothing is worse than one that is plainly out.
    private var isObtainable: Bool {
        store.availability[choice.model.id]?.isObtainable != false
    }
}

#Preview("Footer") {
    WelcomeFooter(choice: ModelChoice.all(for: MemoryBudget(physicalMemory: 16 << 30))[0])
        .frame(width: 1000)
        .background(Color.canvasBackground)
        .environment(WelcomeGate(isShowing: true))
        .environment(GenerationStore.preview(state: .idle))
}
