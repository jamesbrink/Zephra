import Foundation

/// What `releases/latest.json` says the newest published Zephra is: where its disk image lives,
/// the version and build stamped into the app inside it, and that image's SHA-256.
///
/// `scripts/publish-download.sh` writes exactly these four fields beside the immutable stamped
/// DMG it just uploaded, so nothing here is a second description of a release — it is the one
/// the publish already produced.
///
/// **Newer is a build number, never a version.** Every build is `0.1.0` until further notice
/// (see "Build & run" in AGENTS.md), so the version says nothing at all about which of two
/// builds is later. The build is the UTC minute the build started, `YYYYMMDDHHMM`, which
/// compares as an integer. Anything that is not twelve digits is not one of those stamps —
/// `project.yml`'s own default is `1` — and is never newer than anything, so a development
/// build and a hand-stamped build are both simply left alone.
public struct ReleaseManifest: Codable, Hashable, Sendable {
    /// The immutable, stamped disk image: `.../releases/Zephra-0.1.0-<build>.dmg`.
    public var url: URL
    /// The marketing version inside it, for the sentence a person reads.
    public var version: String
    /// `CFBundleVersion` inside it: the UTC minute the build started.
    public var build: String
    /// The disk image's SHA-256, lowercase hex, as `shasum -a 256` writes it.
    public var sha256: String

    public init(url: URL, version: String, build: String, sha256: String) {
        self.url = url
        self.version = version
        self.build = build
        self.sha256 = sha256
    }

    /// How many digits a build stamp has: `YYYYMMDDHHMM`.
    public static let stampDigits = 12

    /// Whether `build` is one of Zephra's build stamps: exactly twelve ASCII digits. Spelled
    /// over the ASCII digits themselves rather than `Int(_:)`, which accepts a sign, Eastern
    /// Arabic numerals and other things a build number is not.
    public static func isStamp(_ build: String) -> Bool {
        build.count == stampDigits && build.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// Whether this release's own build is a stamp.
    public var isStamp: Bool { Self.isStamp(build) }

    /// Whether this release is later than the build `other` names.
    ///
    /// Both have to be stamps for the question to mean anything: a build that is not one is
    /// not on the ladder, and answering "newer" for it would offer a shipped release to a
    /// development build — which `UpdateEligibility` refuses anyway, but the comparison should
    /// not have said yes in the first place.
    public func isNewer(than other: String) -> Bool {
        guard Self.isStamp(build), Self.isStamp(other),
              let mine = Int64(build), let theirs = Int64(other)
        else { return false }
        return mine > theirs
    }

    /// The sentence a banner or a menu says about this release.
    public var line: String { "Zephra \(version) (build \(build))" }
}
