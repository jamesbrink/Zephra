import Foundation

/// The keys and starting values behind every `@AppStorage` in the app, in one place so a
/// preference is never spelled two different ways.
enum AppSettings {
    /// The prompt text, restored on the next launch.
    static let lastPrompt = "lastPrompt"
    /// Whether the filmstrip of this session's images is showing.
    static let filmstripVisible = "filmstripVisible"
    /// Whether every run picks a fresh seed instead of repeating the last one.
    static let randomizeSeedEachRun = "randomizeSeedEachRun"
    /// Whether the model runs a throwaway generation after loading.
    static let warmUpOnLaunch = "warmUpOnLaunch"

    /// Starting values, matching the defaults written at each `@AppStorage` site.
    static let initialFilmstripVisible = true
    /// A fresh seed each run is the friendlier default; a fixed seed is the deliberate choice.
    static let initialRandomizeSeedEachRun = true
    /// Warming up costs a second at launch and saves several on the first real image.
    static let initialWarmUpOnLaunch = true

    /// Where finished images are written when the user has not chosen somewhere else.
    static var defaultOutputDirectory: URL {
        URL.picturesDirectory.appending(path: "Zephra", directoryHint: .isDirectory)
    }
}
