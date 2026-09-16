import ZephraCore
import ZephraEngine

/// Where the chosen model stands: not loaded, on its way in, in, or lost.
///
/// Pure, so the toolbar's word and the button beside it are one answer tested without a window.
/// Loadedness is a word and never a second dot: `ModelDot` means the model's identity, and a
/// mark carrying two meanings reads as neither.
enum ModelLoadStatus: Hashable {
    /// Nothing is in, and nothing is on its way.
    case notLoaded
    /// The weights are being read in.
    case loading
    /// The files are being fetched first.
    case downloading
    /// The release is being packed into the variant this Mac runs.
    case building
    /// The weights are in, read from disk every step when `streamed`.
    case loaded(streamed: Bool)
    /// The last attempt ended in a failure the canvas is showing.
    case failed
    /// The GPU has stopped running this launch's work, and only a relaunch gets it back.
    case lost

    /// What the chosen model's state is, from the engine's own state and what is actually in.
    ///
    /// `chosen` rather than the model being prepared: the toolbar names the model a press of
    /// Generate would run, and a picture picked off the sidebar moves that without moving the
    /// weights. A model in while a different one is chosen reads as not loaded, which is what
    /// it is for the model named beside it.
    static func status(
        of chosen: ModelDescriptor,
        state: EngineState,
        loaded: ModelDescriptor?,
        residency: WeightResidency?
    ) -> ModelLoadStatus {
        switch state {
        // A lost GPU is its own reading, not a failure with a different message: the pill's
        // word is the remedy, and over this one the remedy is not to try again.
        case .failed(.deviceLost): return .lost
        case .failed: return .failed
        case .downloading: return .downloading
        case .building: return .building
        case .checkingModel, .loading, .warmingUp: return .loading
        default: break
        }
        guard loaded?.id == chosen.id else { return .notLoaded }
        return .loaded(streamed: residency == .streamed)
    }

    /// The fragment after the model's name in the toolbar's label, or nil when the plain name
    /// says everything. Nothing is said about a model simply not loaded: the button beside it
    /// already reads Load.
    var word: String? {
        switch self {
        case .notLoaded: nil
        case .loading: "Loading\u{2026}"
        case .downloading: "Downloading"
        case .building: "Building"
        case .loaded(let streamed): streamed ? "Streaming" : "Loaded"
        case .failed: "Failed"
        case .lost: "GPU lost"
        }
    }

    /// What the button beside the menu says. Never nothing: a control that leaves the toolbar
    /// for the length of a load slides the inspector toggle and Settings across and back again,
    /// which is a bigger movement than the pill's own.
    ///
    /// While the weights are on their way in it still reads Load and is out. Not the state word
    /// — the menu beside it already carries that, and "Z-Image Turbo · 8-bit · Downloading"
    /// with "Downloading" greyed out immediately to its right says one thing twice, in a strip
    /// that would then change width on every state. Load is the press the person wants and
    /// cannot have yet, which is what a greyed button means. Stopping a load is the canvas's
    /// button, beside the bar that says how far along it is.
    var buttonTitle: String {
        switch self {
        case .notLoaded, .loading, .downloading, .building: "Load"
        case .loaded: "Unload"
        case .failed: "Try Again"
        // The canvas's Relaunch Zephra is the press, beside the sentence that says why, as the
        // canvas's Stop is the press that stops a load. What this control owes the person is
        // not naming a remedy that no longer exists: Try Again over a driver that refuses
        // every command buffer is a button that fails in a third of a second.
        case .lost: "Relaunch"
        }
    }

    /// Whether the button does anything at all when pressed. False while the model is on its
    /// way in, where the answer is to wait or to stop it from the canvas.
    var isPressable: Bool {
        switch self {
        case .notLoaded, .loaded, .failed: true
        case .loading, .downloading, .building, .lost: false
        }
    }

    /// Whether the button's press is a load rather than an unload, which is what decides
    /// which of `canLoad` and `canUnload` greys it.
    var pressLoads: Bool {
        switch self {
        case .loaded: false
        default: true
        }
    }

    /// The button's tooltip: what the press costs, naming the model that has to go first when
    /// something else is holding the memory. The sentence rather than the word, because this
    /// is the one place a press that unloads one model to load another can say so.
    func help(chosen: ModelDescriptor, loaded: ModelDescriptor?) -> String {
        switch self {
        case .notLoaded:
            let first = loaded.map { " Unloads \($0.fullName) first." } ?? ""
            return "Loads \(chosen.fullName)." + first
        case .loaded(let streamed):
            let how = streamed
                ? " Its weights are read from the disk on every step." : ""
            return "Unloads \(chosen.fullName) and gives its memory back." + how
        case .failed:
            return "Tries loading \(chosen.fullName) again."
        case .loading, .downloading, .building:
            return "\(chosen.fullName) is on its way in."
        case .lost:
            return "Zephra has lost the GPU. Relaunch it from the canvas to get it back."
        }
    }
}
