import Foundation

extension UpdatePhase {
    /// What the banner says. One sentence per phase, naming the build rather than the version,
    /// since every version is 0.1.0 and the build is the only thing that tells two apart.
    var sentence: String {
        switch self {
        case .idle, .checking:
            ""
        case .available(let release):
            "\(release.line) is available."
        case .downloading:
            "Downloading the update…"
        case .ready:
            "The update is ready to install."
        case .installing:
            "Installing… Zephra will restart."
        case .failed(let reason):
            reason
        }
    }

    /// What the button that puts the banner away is called: a failure is dismissed, a release
    /// is put off until the next launch.
    var dismissTitle: String {
        if case .failed = self { return "Dismiss" }
        return "Later"
    }
}
