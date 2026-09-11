import Foundation
import Security

/// A keychain call that did not work, with the code it gave.
///
/// Carried rather than swallowed: a locked keychain is not an empty list of devices, and
/// treating it as one would quietly unpair every phone.
struct LinkKeychainFailure: Error, LocalizedError {
    /// The `OSStatus` the Security framework returned.
    let status: OSStatus

    /// Whether this is the data-protection keychain saying this build may not use it, which is
    /// answered by falling back to the old keychain rather than by failing.
    var isMissingEntitlement: Bool { status == errSecMissingEntitlement }

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"
        return "The keychain could not be read or written: \(detail)"
    }
}
