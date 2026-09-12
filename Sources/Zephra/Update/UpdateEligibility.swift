import Foundation
import ZephraSnapshot

/// Whether this copy of Zephra is one that may replace itself, and why not when it is not.
///
/// The installer moves the running bundle aside and copies another over it, which is a thing
/// to do to a shipped app in `/Applications` and to nothing else. Three copies are refused,
/// in this order, because the earlier answers are the truer ones:
///
/// 1. **Translocated.** Gatekeeper runs an app opened straight out of a disk image or the
///    Downloads folder from a read-only mirror under `/private/var/folders/.../AppTranslocation/`.
///    Its `bundleURL` says nothing about where the app really is, so nothing may be written
///    anywhere near it; the answer is to drag it to Applications, which is what the sentence says.
/// 2. **A development build.** A build number that is not a twelve-digit stamp is not on the
///    ladder `ReleaseManifest.isNewer(than:)` compares along — `project.yml`'s default is `1` —
///    so a `make build` copy is never offered a shipped release over itself.
/// 3. **Not in Applications.** `/Applications` or `~/Applications`, and nowhere else: a copy
///    sitting in Downloads beside its disk image, or one inside another app's bundle, is not a
///    copy anything should be swapping out from under its owner.
///
/// The last is lifted for a launch with `ZEPHRA_UPDATE_FEED` or `ZEPHRA_UPDATE_BUILD` set,
/// since the hand test is exactly a Debug build in `build/Debug` pointed at a local feed; the
/// first two are not, and a Debug build still has to be given a stamp to be offered anything.
enum UpdateEligibility: Hashable, Sendable {
    case eligible
    case translocated
    case developmentBuild
    case notInApplications

    /// Whether the installer may run at all.
    var canInstall: Bool { self == .eligible }

    /// What to tell someone who asked for an update this copy cannot take, or nil when it can.
    var refusal: String? {
        switch self {
        case .eligible:
            nil
        case .translocated:
            """
            Zephra is running from its disk image, so it cannot update itself. \
            Drag Zephra to your Applications folder and open it from there.
            """
        case .developmentBuild:
            "This is a development build of Zephra, so it does not update itself."
        case .notInApplications:
            """
            Zephra updates itself only from your Applications folder. \
            Move Zephra there and open it again.
            """
        }
    }

    /// The verdict for a copy with this build number, at this path.
    ///
    /// Pure, so every case is a test rather than a thing to try on a real Mac; `current` is the
    /// one place it is asked about this process.
    static func of(
        build: String, bundle: URL, home: URL, overridden: Bool
    ) -> UpdateEligibility {
        let path = bundle.standardizedFileURL.path(percentEncoded: false)
        if path.contains("/AppTranslocation/") { return .translocated }
        guard ReleaseManifest.isStamp(build) else { return .developmentBuild }
        guard !overridden else { return .eligible }
        let folders = [
            "/Applications/",
            home.standardizedFileURL.appending(path: "Applications").path(percentEncoded: false) + "/",
        ]
        guard folders.contains(where: { path.hasPrefix($0) }) else { return .notInApplications }
        // A folder of one's own inside Applications is fine; inside another app's bundle is
        // not — that copy belongs to the app around it, whatever the prefix says.
        let enclosing = bundle.standardizedFileURL.pathComponents.dropLast()
        return enclosing.contains { $0.hasSuffix(".app") } ? .notInApplications : .eligible
    }

    /// The verdict for the running copy, under `environment`.
    static func current(_ environment: UpdateEnvironment) -> UpdateEligibility {
        of(
            build: RunningBuild.number(pretending: environment.pretendBuild),
            bundle: Bundle.main.bundleURL,
            home: FileManager.default.homeDirectoryForCurrentUser,
            overridden: environment.isOverridden)
    }
}
