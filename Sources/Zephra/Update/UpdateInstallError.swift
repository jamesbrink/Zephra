import Foundation

/// Why a downloaded Zephra was not put in place.
///
/// Every case is a sentence a person can act on, because every one of them is a thing that
/// stops here rather than something to retry: a disk image that will not mount, an app that is
/// not signed by us, a Gatekeeper refusal, a build that is not the one the manifest promised,
/// or a folder this copy may not write to.
enum UpdateInstallError: Error, Hashable, Sendable {
    /// The disk image would not mount.
    case mountFailed(reason: String)
    /// There is no Zephra inside it.
    case notAZephra
    /// Its signature does not check out.
    case signatureInvalid(reason: String)
    /// macOS itself will not run it.
    case gatekeeperRefused(reason: String)
    /// It is signed, and by somebody else.
    case differentSigner
    /// Its `Info.plist` is not the release the manifest named.
    case wrongApp(reason: String)
    /// The folder Zephra is in cannot be written to, so it cannot replace itself.
    case cannotReplaceItself(folder: String)
    /// The copy into place did not finish; whatever was moved aside has been put back.
    case copyFailed(reason: String)
    /// The copy failed *and* putting the original back failed, so there is no Zephra where
    /// there was one. Nothing can be done about that automatically, so the sentence says where
    /// the app actually is and what to rename it to.
    case rollbackFailed(aside: String)

    /// What to tell someone, without the jargon of the layer it came from.
    var message: String {
        switch self {
        case .mountFailed(let reason):
            "The downloaded disk image could not be opened: \(reason)"
        case .notAZephra:
            "The download is not a copy of Zephra."
        case .signatureInvalid(let reason):
            "The downloaded Zephra is not correctly signed: \(reason)"
        case .gatekeeperRefused(let reason):
            "macOS will not run the downloaded Zephra: \(reason)"
        case .differentSigner:
            "The downloaded Zephra was signed by somebody else, so it was not installed."
        case .wrongApp(let reason):
            reason
        case .cannotReplaceItself(let folder):
            """
            Zephra cannot write to \(folder), so it cannot replace itself. \
            Open the downloaded disk image and drag Zephra there yourself.
            """
        case .copyFailed(let reason):
            "The update could not be put in place: \(reason)"
        case .rollbackFailed(let aside):
            """
            The update could not be put in place, and Zephra could not be moved back. \
            Your copy of Zephra is at \(aside); rename it back to Zephra.app.
            """
        }
    }

    /// Whether the disk image is still worth showing the person, so they can install it by
    /// hand. It is, for the one failure that is about this Mac's folders rather than about the
    /// download itself.
    var offersTheDiskImage: Bool {
        if case .cannotReplaceItself = self { return true }
        return false
    }
}
