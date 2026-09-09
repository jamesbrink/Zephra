import Foundation
import Observation
import ZephraCore

/// Whether the window is showing the first-launch model chooser instead of the workspace.
///
/// A first launch used to start a thirteen-gigabyte download before the window had finished
/// appearing, on a model nobody had picked. This is the one flag that stops that: while it is
/// up the root asks the engine only what is on disk, never for weights, and the chooser says
/// what each model would cost before one is fetched.
///
/// Resolved from the preferences synchronously, in `init`, so a launch that has never chosen
/// opens on the chooser rather than flashing the canvas first.
@Observable
@MainActor
final class WelcomeGate {
    /// Whether the chooser is up.
    private(set) var isShowing: Bool

    /// Where the answer is read and written. Injected so a test drives a domain of its own
    /// rather than the preferences a person is using.
    @ObservationIgnored private let defaults: UserDefaults

    /// The gate as a launch finds it: up on a Mac that has never answered the question.
    init(defaults: UserDefaults = AppSettings.store) {
        self.defaults = defaults
        isShowing = InterfacePreview.wantsWelcome || !Self.hasAnswered(in: defaults)
    }

    /// A gate in a known state, for a preview and for a test.
    init(isShowing: Bool, defaults: UserDefaults = AppSettings.store) {
        self.defaults = defaults
        self.isShowing = isShowing
    }

    /// Whether this Mac has already been past the question.
    ///
    /// The flag is the answer once it has been written. Before that, a `selectedModelID` is
    /// what says a Zephra has run here before: the composition root writes it on every launch,
    /// first or not, so its absence is what a genuinely first launch looks like — and reading
    /// it is what keeps the chooser from appearing, however briefly, in front of somebody who
    /// has been using Zephra since before it existed.
    static func hasAnswered(in defaults: UserDefaults) -> Bool {
        if defaults.object(forKey: AppSettings.hasChosenModel) as? Bool == true { return true }
        return defaults.object(forKey: AppSettings.selectedModelID) != nil
    }

    /// Settles the chooser against what the disk turned out to hold, once the survey lands,
    /// and answers the model to continue on — or nil to leave the chooser up.
    ///
    /// A Mac that already has a model — `make prefetch`, a warm Hugging Face cache, a
    /// reinstall over the same models folder — is not asked to choose one: there is nothing to
    /// download and nothing to decide. Which model it continues on is the whole of the answer
    /// and is why this returns one rather than only closing: the store is still pointing at
    /// `ModelCatalog.default(fitting:)`, which on such a Mac is very often not the model that
    /// is actually here, and continuing on that would download a second model to sit beside
    /// the one already downloaded.
    ///
    /// Answering nil for a chooser that is already down is what keeps a Skip pressed while the
    /// survey was still running from turning into a download: the answer was "not now", and a
    /// survey landing a moment later must not overrule it.
    func settle(
        availability: [ModelDescriptor.ID: ModelAvailability],
        budget: MemoryBudget,
        current: ModelDescriptor
    ) -> ModelDescriptor? {
        // A screenshot build is asked for the chooser and gets it: its frozen store reports
        // the chosen model as downloaded, which would otherwise put the screen away before it
        // could be photographed.
        guard isShowing, !InterfacePreview.wantsWelcome else { return nil }
        guard let ready = Self.readyModel(availability: availability, budget: budget, current: current)
        else { return nil }
        dismiss()
        return ready
    }

    /// The model to continue on when the disk already holds one: the store's own choice when
    /// that is what is here, and otherwise the first model this Mac would be offered that is.
    static func readyModel(
        availability: [ModelDescriptor.ID: ModelAvailability],
        budget: MemoryBudget,
        current: ModelDescriptor
    ) -> ModelDescriptor? {
        if availability[current.id] == .available { return current }
        return ModelCatalog.ordered(for: budget).first { availability[$0.id] == .available }
    }

    /// Records that the question has been answered and shows the workspace. Both picking a
    /// model and skipping past the chooser come through here, because both are answers.
    func dismiss() {
        isShowing = false
        defaults.set(true, forKey: AppSettings.hasChosenModel)
    }

    /// Shows the chooser again, from the canvas of a session that skipped it or cancelled the
    /// download it started.
    func reopen() {
        isShowing = true
    }
}
