import Foundation

/// What build this copy of Zephra is, and what bundle identifier it carries.
///
/// The build number is `CFBundleVersion`, the UTC minute the build started, which is the one
/// thing that tells two Zephras apart while every version is 0.1.0. `ZEPHRA_UPDATE_BUILD` is
/// allowed to answer for it, so a Debug hand run can claim to be older than a published
/// release without a release being shipped for it.
///
/// Separate from `AppFacts`, which is what the app *says* about itself on screen: this is what
/// the updater *compares*, and a version line a person reads and a stamp two builds are ordered
/// by are not the same fact wearing two names.
enum RunningBuild {
    /// This build's number, or the one a Debug launch asked to pretend to be.
    static func number(pretending: String? = nil) -> String {
        if let pretending, !pretending.isEmpty { return pretending }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    }

    /// This build's marketing version, for a sentence rather than a comparison.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    /// The identifier a downloaded Zephra has to carry to be accepted as this app's next
    /// version. An app with another identifier is another app.
    static var identifier: String { Bundle.main.bundleIdentifier ?? "io.zephra.Zephra" }
}
