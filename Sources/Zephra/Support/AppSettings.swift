import Foundation
import ZephraCore

/// The keys and starting values behind every `@AppStorage` in the app, in one place so a
/// preference is never spelled two different ways.
enum AppSettings {
    /// The prompt text, restored on the next launch.
    static let lastPrompt = "lastPrompt"
    /// Whether the strip of this run's images is showing under the capsule.
    static let filmstripVisible = "filmstripVisible"
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

    /// Starting values, matching the defaults written at each `@AppStorage` site.
    static let initialFilmstripVisible = true
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
    /// One image per press, until the user asks for more.
    static let initialBatchCount = 1

    /// How the stored preference and this machine's memory decide the VAE tile, for the
    /// composition root, which has to answer the question outside a picker.
    static func tilingPolicy() -> VAETilingPolicy {
        let stored = UserDefaults.standard.string(forKey: vaeTiling)
        return VAETilingPolicy(
            mode: stored.flatMap(VAETilingMode.init(rawValue:)) ?? initialVAETiling,
            physicalMemory: ProcessInfo.processInfo.physicalMemory
        )
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
        case filmstripVisible: initialFilmstripVisible
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
