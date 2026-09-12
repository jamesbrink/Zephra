import Foundation
import ZephraSnapshot

/// What a check somebody asked for came to, in the two strings an alert needs.
///
/// Only the menu item raises one of these. A check that ran on its own timer and found nothing
/// says nothing at all: an alert nobody asked for, over a window somebody is working in, to
/// report that everything is as it was, is the thing that makes people switch updates off.
enum UpdateOutcome: Hashable, Sendable {
    /// Nothing newer is published.
    case upToDate(version: String)
    /// There is, and the banner is now showing it.
    case available(ReleaseManifest)
    /// The check itself did not work.
    case failed(reason: String)
    /// This copy of Zephra is not one that updates itself.
    case ineligible(reason: String)

    /// The alert's first line.
    var message: String {
        switch self {
        case .upToDate: "Zephra is up to date."
        case .available: "An update is available."
        case .failed: "Zephra could not check for updates."
        case .ineligible: "Zephra cannot update itself."
        }
    }

    /// The alert's second line.
    var detail: String {
        switch self {
        case .upToDate(let version): version
        case .available(let release): "\(release.line) is ready to install."
        case .failed(let reason): reason
        case .ineligible(let reason): reason
        }
    }
}
