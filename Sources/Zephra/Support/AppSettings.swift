import Foundation
import ZephraCore
import ZephraEngine
import ZephraStyle

/// The keys and starting values behind every `@AppStorage` in the app, in one place so a
/// preference is never spelled two different ways.
enum AppSettings {
    /// Where every preference below is read and written.
    ///
    /// `UserDefaults.standard` for an ordinary launch, and a suite of its own under
    /// `FreshStart`, so a launch pretending to be a new Mac neither reads a person's
    /// preferences nor writes over them. Resolved once: the store cannot change under a
    /// running app. Views bind through it because the composition root hands it to
    /// `.defaultAppStorage`, and the code that reads a preference outside a view reads it
    /// here.
    static let store: UserDefaults = {
        guard let suite = FreshStart.current?.preferences() else { return .standard }
        return suite
    }()

    /// The prompt text, restored on the next launch.
    static let lastPrompt = "lastPrompt"
    /// Whether every run picks a fresh seed instead of repeating the last one.
    static let randomizeSeedEachRun = "randomizeSeedEachRun"
    /// Whether the model runs a throwaway generation after loading.
    static let warmUpOnLaunch = "warmUpOnLaunch"
    /// Whether a saved image, a finished download or a published update is announced while the
    /// app is in the background.
    static let backgroundNotifications = "backgroundNotifications"
    /// Whether Zephra looks for a newer published build on its own. The look is one small
    /// request; nothing is fetched, and nothing is installed, without a press.
    static let checksForUpdates = "checksForUpdates"
    /// The `ModelDescriptor.id` chosen in the model menu, restored on the next launch.
    static let selectedModelID = "selectedModelID"
    /// Whether the first-launch chooser has been answered, either by picking a model or by
    /// skipping past it. Deliberately not inferred from `selectedModelID`, which the
    /// composition root writes on every launch, first or not.
    static let hasChosenModel = "hasChosenModel"
    /// Ceiling on the GPU scratch the runtime retains between generations, in megabytes.
    /// Unset means the recommendation `InferenceTuning` works out for this machine.
    static let cacheLimitMB = "cacheLimitMB"
    /// When the VAE decode runs in tiles, as a `VAETilingMode` raw value.
    static let vaeTiling = "vaeTiling"
    /// When a model's weights are streamed from disk rather than held, as a
    /// `WeightResidencyMode` raw value.
    static let weightResidency = "weightResidency"
    /// Which pane the window was showing, as a `WorkspacePane` raw value.
    static let workspacePane = "workspacePane"
    /// The collection the library was showing, as a `LibraryScope` raw value.
    static let libraryScope = "libraryScope"
    /// The order it was listed in, as a `LibrarySort` raw value.
    static let librarySort = "librarySort"
    /// Whether the library's inspector is open.
    static let inspectorVisible = "inspectorVisible"
    /// The edge of one library thumbnail, in points.
    static let libraryThumbnailEdge = "libraryThumbnailEdge"
    /// How many seeds one press of Generate queues.
    static let batchCount = "batchCount"
    /// How a seed is written wherever one is shown, as a `SeedFormat` raw value.
    static let seedFormat = "seedFormat"
    /// Whether the app follows the Mac's appearance or fixes its own, as an `AppearanceMode`
    /// raw value.
    static let appearance = "appearance"
    /// The folder models are downloaded and built in, as a plain path. Empty means the app's
    /// own folder under Application Support. The app is not sandboxed, so a path is enough:
    /// no security-scoped bookmark is needed to read a folder the user pointed at.
    static let modelsDirectory = "modelsDirectory"
    /// The image library folder. Empty means ~/Pictures/Zephra.
    static let imagesDirectory = "imagesDirectory"
    /// The folders `modelsDirectory` was set to before, newest first, so what was put there
    /// is still found. Never more than a handful.
    static let previousModelsDirectories = "previousModelsDirectories"
    /// Whether a paired iPhone may connect to this Mac at all. Off until it is asked for: the
    /// link opens a port and advertises the Mac on the network, and neither should happen
    /// because somebody installed the app.
    static let companionEnabled = "companionEnabled"
    /// Whether a phone that cannot reach this Mac directly may meet it on the relay. Off on its
    /// own: reaching the Mac from outside the house is a second thing to agree to, and the
    /// first one does not imply it.
    static let companionRelayEnabled = "companionRelayEnabled"
    /// The relay to meet on, as a URL. Overridable so a person running their own relay can
    /// point at it, and so a test build can point somewhere harmless.
    static let companionRelayURL = "companionRelayURL"
    /// What the Mac calls itself on a phone's list of Macs. The machine's own name until the
    /// person changes it.
    static let companionDeviceName = "companionDeviceName"

    // Starting values, matching the defaults written at each `@AppStorage` site.

    /// A fresh seed each run is the friendlier default; a fixed seed is the deliberate choice.
    static let initialRandomizeSeedEachRun = true
    /// Warming up costs a second at launch and saves several on the first real image.
    static let initialWarmUpOnLaunch = true
    /// A run and a download are both things a person walks away from.
    static let initialBackgroundNotifications = true
    /// On, because a Mac quietly running an old build is the failure mode worth avoiding; the
    /// check itself is a hundred bytes every six hours and fetches nothing.
    static let initialChecksForUpdates = true
    /// Exactness wherever the Mac has the memory for it, tiling only where it does not.
    static let initialVAETiling = VAETilingMode.automatic
    /// Resident wherever the Mac can hold the model, streamed only where it cannot.
    static let initialWeightResidency = WeightResidencyMode.automatic
    /// The library opens with its inspector out: the facts about an image are why it is there.
    static let initialInspectorVisible = true
    /// Big enough to judge an image by, small enough for a wall of them.
    static let initialLibraryThumbnailEdge = 168.0
    /// How far the size slider goes: a contact sheet at one end, a few big pictures at the
    /// other. The ends match the smallest and largest `ThumbnailSize` closely enough that
    /// nothing is ever scaled up much or baked far larger than it is drawn.
    static let libraryThumbnailEdgeBounds = 96.0...320.0
    /// One image per press, until the user asks for more.
    static let initialBatchCount = 1
    /// The short hex label: eight characters that fit a chip and tell two seeds apart.
    static let initialSeedFormat = SeedFormat.hex
    /// The Mac's own appearance, until the user picks one.
    static let initialAppearance = AppearanceMode.system
    /// A phone connects only once somebody has said it may.
    static let initialCompanionEnabled = false
    /// And reaches the Mac from outside the house only once they have said that too.
    static let initialCompanionRelayEnabled = false
    /// The relay Zephra runs. A pipe that copies sealed bytes and has no key to read them.
    static let initialCompanionRelayURL = "wss://zephra-link.urandom.io"

    /// What this Mac is called on a phone. The machine's own name until it is changed here,
    /// and never empty: a nameless Mac on a list of Macs is one nobody can pick.
    static func companionName() -> String {
        let stored = store.string(forKey: companionDeviceName)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard stored.isEmpty else { return stored }
        return Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    /// Where the relay is, or nil when the person has not allowed one. An unparseable URL is
    /// nil too: a relay that cannot be dialled is the same as no relay, and the local network
    /// is unaffected either way.
    static func companionRelay() -> URL? {
        guard flag(companionRelayEnabled) else { return nil }
        let stored = store.string(forKey: companionRelayURL) ?? initialCompanionRelayURL
        return URL(string: stored)
    }

    /// Where models are kept right now, for the composition root, which has to answer the
    /// question before any view exists. An unset or empty path is the app's own folder.
    static func modelLocations() -> ModelLocations {
        let defaults = store
        let stored = defaults.string(forKey: modelsDirectory) ?? ""
        let previous = (defaults.stringArray(forKey: previousModelsDirectories) ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        // An unset preference is the app's own folder, or the fresh start's when this launch
        // is pretending to be a new Mac; a folder the user picked is theirs either way.
        let root = stored.isEmpty
            ? (FreshStart.current?.models ?? ModelLocations.default.root)
            : URL(filePath: stored, directoryHint: .isDirectory)
        return ModelLocations(root: root, previous: previous)
    }

    /// Records that the models folder moved from `old` to `new`, keeping the last few roots
    /// so nothing under them is lost to the lookup. The default folder is stored as an empty
    /// path so that a later change of default is picked up.
    static func recordModelsDirectory(_ new: URL?, leaving old: URL) {
        let locations = proposedModelLocations(new, leaving: old)
        let defaults = store
        defaults.set(locations.previous.map { $0.path(percentEncoded: false) }, forKey: previousModelsDirectories)
        defaults.set(new?.path(percentEncoded: false) ?? "", forKey: modelsDirectory)
    }

    /// The exact settings to apply, without persisting a choice that may still fail.
    static func proposedModelLocations(_ new: URL?, leaving old: URL) -> ModelLocations {
        let root = new ?? ModelLocations.default.root
        var seen: Set<String> = [root.standardizedFileURL.path]
        let previous = ([old] + modelLocations().previous)
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
            .prefix(5)
        return ModelLocations(root: root, previous: Array(previous))
    }

    /// A stored flag as it stands right now, for the code that has to read one outside a view
    /// and so cannot use `@AppStorage`. An unset key falls back to the same starting value the
    /// views use, so a preference means one thing everywhere.
    static func flag(_ key: String) -> Bool {
        store.object(forKey: key) as? Bool ?? initialValue(of: key)
    }

    /// A stored whole number as it stands right now, for the same reason `flag(_:)` exists.
    static func integer(_ key: String) -> Int {
        store.object(forKey: key) as? Int ?? initialInteger(of: key)
    }

    /// Stores one preference from outside a view, for state an `@Observable` owns rather than
    /// an `@AppStorage`. The reading half of the same pair is `flag(_:)` for a switch and
    /// `UserDefaults` for a raw value that is parsed back into its own type.
    static func write(_ value: some Sendable, to key: String) {
        store.set(value, forKey: key)
    }

    private static func initialValue(of key: String) -> Bool {
        switch key {
        case randomizeSeedEachRun: initialRandomizeSeedEachRun
        case warmUpOnLaunch: initialWarmUpOnLaunch
        case backgroundNotifications: initialBackgroundNotifications
        case checksForUpdates: initialChecksForUpdates
        case inspectorVisible: initialInspectorVisible
        case companionEnabled: initialCompanionEnabled
        case companionRelayEnabled: initialCompanionRelayEnabled
        default: false
        }
    }

    private static func initialInteger(of key: String) -> Int {
        switch key {
        case batchCount: initialBatchCount
        default: 0
        }
    }
}
