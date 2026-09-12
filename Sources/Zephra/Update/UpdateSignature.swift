import Foundation
import Security

/// Who signed a copy of Zephra, so a download signed by somebody else is never copied over
/// this one.
///
/// `codesign --verify` says a signature is intact and `spctl` says macOS will run it. Neither
/// says it is *ours*: Gatekeeper accepts any notarized Developer ID app, so an app from
/// another team carrying Zephra's bundle identifier and the published build number would pass
/// both checks. The team identifier is what closes that, read through the Security framework
/// rather than by parsing `codesign`'s output.
///
/// **It is compared against a constant, and it fails closed.** The team is
/// `AppFacts.teamIdentifier`, not whatever `SecCodeCopySelf` says about this process: that
/// call and `SecCodeCopySigningInformation` have several ways to answer nothing, none of them
/// distinguishable from "ad-hoc", and an earlier spelling of this check treated every one of
/// them as "nothing to compare, carry on". A check that stands itself down when it cannot run
/// is not a check.
///
/// The one exemption is the Debug hand run: a launch driving its own feed
/// (`UpdateEnvironment.isOverridden`) may accept an unsigned candidate, because what it is
/// exercising is the install and there is no notarized build to hand. Release never skips —
/// `isOverridden` is false there whatever the environment holds, since
/// `UpdateEnvironment.current` reads the hooks only under `#if DEBUG`.
enum UpdateSignature {
    /// The team identifier of the bundle at `url`, or nil when it has none or cannot be read.
    nonisolated static func team(at url: URL) -> String? {
        var candidate: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &candidate) == errSecSuccess,
              let candidate
        else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(
            candidate, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let facts = information as? [String: Any]
        else { return nil }
        return facts[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Whether a download signed by `theirs` may replace this copy. Pure, so every case is a
    /// test rather than something found out on somebody's Mac.
    ///
    /// `ours` is the constant above in every real call; it is a parameter only so a test can
    /// say what it is comparing against. A nil `theirs` — unsigned, or a signature the
    /// Security framework could not read — is refused unless the Debug feed override is
    /// driving the run.
    nonisolated static func matches(
        ours: String = AppFacts.teamIdentifier, theirs: String?, overridden: Bool = false
    ) -> Bool {
        if let theirs, theirs == ours { return true }
        return overridden && theirs == nil
    }
}
