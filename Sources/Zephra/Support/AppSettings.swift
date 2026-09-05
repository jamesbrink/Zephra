import Foundation
import ZephraCore

/// The keys and starting values behind every `@AppStorage` in the app, in one place so a
/// preference is never spelled two different ways.
enum AppSettings {
    /// The prompt text, restored on the next launch.
    static let lastPrompt = "lastPrompt"
    /// Whether every run picks a fresh seed instead of repeating the last one.
    static let randomizeSeedEachRun = "randomizeSeedEachRun"
    /// Whether the model runs a throwaway generation after loading.
    static let warmUpOnLaunch = "warmUpOnLaunch"
    /// The `ModelDescriptor.id` chosen in the model menu, restored on the next launch.
    static let selectedModelID = "selectedModelID"
    /// Ceiling on the GPU scratch the runtime retains between generations, in megabytes.
    /// Unset means the recommendation `InferenceTuning` works out for this machine.
    static let cacheLimitMB = "cacheLimitMB"
    /// When the VAE decode runs in tiles, as a `VAETilingMode` raw value.
    static let vaeTiling = "vaeTiling"
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

    // Starting values, matching the defaults written at each `@AppStorage` site.

    /// A fresh seed each run is the friendlier default; a fixed seed is the deliberate choice.
    static let initialRandomizeSeedEachRun = true
    /// Warming up costs a second at launch and saves several on the first real image.
    static let initialWarmUpOnLaunch = true
    /// Exactness wherever the Mac has the memory for it, tiling only where it does not.
    static let initialVAETiling = VAETilingMode.automatic
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
    /// The Mac's own appearance, until the user picks one.
    static let initialAppearance = AppearanceMode.system

    /// How the stored preference and this machine's memory decide the VAE tile, for the
    /// composition root, which has to answer the question outside a picker.
    static func tilingPolicy() -> VAETilingPolicy {
        let stored = UserDefaults.standard.string(forKey: vaeTiling)
        return VAETilingPolicy(
            mode: stored.flatMap(VAETilingMode.init(rawValue:)) ?? initialVAETiling,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
    }

    /// Where models are kept right now, for the composition root, which has to answer the
    /// question before any view exists. An unset or empty path is the app's own folder.
    static func modelLocations() -> ModelLocations {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: modelsDirectory) ?? ""
        let previous = (defaults.stringArray(forKey: previousModelsDirectories) ?? [])
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
        let root = stored.isEmpty
            ? ModelLocations.default.root : URL(filePath: stored, directoryHint: .isDirectory)
        return ModelLocations(root: root, previous: previous)
    }

    /// Records that the models folder moved from `old` to `new`, keeping the last few roots
    /// so nothing under them is lost to the lookup. The default folder is stored as an empty
    /// path so that a later change of default is picked up.
    static func recordModelsDirectory(_ new: URL?, leaving old: URL) {
        let locations = proposedModelLocations(new, leaving: old)
        let defaults = UserDefaults.standard
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
        UserDefaults.standard.object(forKey: key) as? Bool ?? initialValue(of: key)
    }

    /// A stored whole number as it stands right now, for the same reason `flag(_:)` exists.
    static func integer(_ key: String) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? initialInteger(of: key)
    }

    /// Stores one preference from outside a view, for state an `@Observable` owns rather than
    /// an `@AppStorage`. The reading half of the same pair is `flag(_:)` for a switch and
    /// `UserDefaults` for a raw value that is parsed back into its own type.
    static func write(_ value: some Sendable, to key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func initialValue(of key: String) -> Bool {
        switch key {
        case randomizeSeedEachRun: initialRandomizeSeedEachRun
        case warmUpOnLaunch: initialWarmUpOnLaunch
        case inspectorVisible: initialInspectorVisible
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
