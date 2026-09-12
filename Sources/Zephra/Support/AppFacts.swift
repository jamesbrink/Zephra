import AppKit

/// What the app says about itself: its name, the version line, the copyright — read from the
/// bundle — the website, and the sentence the About window and the About tab both open with.
///
/// One place, because the About window, Settings > About and the standard fields AppKit
/// would have drawn all have to agree, and because `Info.plist` is where the version and the
/// copyright are stamped at build time (`MARKETING_VERSION`, `CURRENT_PROJECT_VERSION`,
/// `NSHumanReadableCopyright` in `project.yml`), so nothing here repeats a figure.
enum AppFacts {
    static let name = "Zephra"

    /// The Apple Developer team every shipped Zephra is signed by, written down rather than
    /// read back from this process.
    ///
    /// The updater compares a downloaded app's team identifier against this literal, and this
    /// is the one fact here that is deliberately *not* taken from the bundle. Asking the
    /// running copy who signed it makes the check only as good as the Security call: any
    /// failure there — and there are several, none of them signalled apart from a nil — would
    /// answer "no team", and a check that skips itself when it cannot run is not a check. A
    /// constant cannot fail to be read.
    ///
    /// `nonisolated` because the installer's verification runs off the main actor.
    nonisolated static let teamIdentifier = "28X9H69QGE"

    /// What Zephra is, in the words a person meeting it for the first time needs: what it
    /// makes, where it runs, and what stays on the Mac.
    static let summary = """
        Zephra makes images and short video clips from a written prompt, running open \
        models locally on your Mac's Apple Silicon. Prompts and pictures stay on your Mac; \
        only the models are downloaded.
        """

    static let website = URL(string: "https://zephra.urandom.io")!

    /// "Version 0.1.0 (1)", the way the standard About panel writes it.
    static var versionLine: String {
        versionLine(version: info("CFBundleShortVersionString"), build: info("CFBundleVersion"))
    }

    /// The version line from its two parts: the marketing version, then the build number in
    /// parentheses when there is one. A build with neither stamped says so rather than
    /// showing an empty pair of parentheses.
    static func versionLine(version: String?, build: String?) -> String {
        guard let version, !version.isEmpty else { return "Development build" }
        guard let build, !build.isEmpty else { return "Version \(version)" }
        return "Version \(version) (\(build))"
    }

    /// The copyright line the bundle carries, or nothing to draw.
    static var copyright: String { info("NSHumanReadableCopyright") ?? "" }

    private static func info(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }
}
