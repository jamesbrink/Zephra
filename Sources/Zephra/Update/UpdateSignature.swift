import Foundation
import Security

/// Who signed a copy of Zephra, so a download signed by somebody else is never copied over
/// this one.
///
/// `codesign --verify` says a signature is intact and `spctl` says macOS will run it; neither
/// says it is *ours*. A Developer ID certificate anyone can buy would pass both, so the team
/// identifier is compared as well, read through the Security framework rather than by parsing
/// `codesign`'s output.
///
/// A running copy with no team identifier is an ad-hoc build — every `make build` is one — and
/// there is nothing to compare against, so the check is skipped rather than failed. That is not
/// a hole: `UpdateEligibility` has already refused a development build, and a Debug hand run
/// has deliberately been pointed at a feed of its own.
enum UpdateSignature {
    /// The team identifier of the running process, or nil when it is ad-hoc signed.
    nonisolated static var ours: String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var static_: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &static_) == errSecSuccess, let static_ else { return nil }
        return teamIdentifier(of: static_)
    }

    /// The team identifier of the bundle at `url`, or nil when it has none.
    nonisolated static func team(at url: URL) -> String? {
        var static_: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &static_) == errSecSuccess,
              let static_
        else { return nil }
        return teamIdentifier(of: static_)
    }

    /// Whether a download signed by `theirs` may replace a copy signed by `ours`. Pure, so the
    /// three cases are a test rather than something found out on somebody's Mac.
    nonisolated static func matches(ours: String?, theirs: String?) -> Bool {
        guard let ours else { return true }
        return ours == theirs
    }

    private nonisolated static func teamIdentifier(of code: SecStaticCode) -> String? {
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &information)
            == errSecSuccess,
            let facts = information as? [String: Any]
        else { return nil }
        return facts[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
