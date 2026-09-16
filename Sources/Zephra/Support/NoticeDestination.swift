import Foundation

/// Where clicking one of Zephra's notifications takes the person, when it takes them anywhere
/// more particular than the window.
///
/// Most notices are about the window itself — a download finished, an update is ready — and
/// bringing it forward is the whole of what they mean. A saved picture is the exception: the
/// thing it is about is a file, and the person who walked away wants to see that file rather
/// than whatever the window happens to be showing when they come back.
///
/// It crosses the notification centre as plain strings in `userInfo`, which is all that may be
/// put there, and comes back through `init?(userInfo:)`. Both halves are here and neither
/// imports UserNotifications, so the round trip is tested without one. Anything unrecognised
/// reads as nil: a notification posted by an older Zephra and clicked after an update carries
/// keys this build has never heard of, and the honest answer to those is "no destination".
nonisolated enum NoticeDestination: Equatable {
    /// One picture or clip in the library, by the file name the library resolves it under.
    case library(fileName: String)

    /// Which kind of destination this is, so an unknown one can be recognised as unknown.
    private static let kindKey = "io.zephra.notice.destination"
    /// The file name a library destination names.
    private static let nameKey = "io.zephra.notice.fileName"
    private static let libraryKind = "library"

    /// The destination as the strings a notification may carry.
    var userInfo: [String: String] {
        switch self {
        case .library(let fileName):
            [Self.kindKey: Self.libraryKind, Self.nameKey: fileName]
        }
    }

    /// The destination a clicked notification carried, or nil when it carried none.
    init?(userInfo: [AnyHashable: Any]) {
        guard let kind = userInfo[Self.kindKey] as? String, kind == Self.libraryKind,
              let fileName = userInfo[Self.nameKey] as? String, !fileName.isEmpty
        else { return nil }
        self = .library(fileName: fileName)
    }
}

extension BackgroundNotice {
    /// Where a click on this notice goes, or nil when it goes no further than the window.
    ///
    /// Only the saved picture has one. A finished download is about a model that is now on the
    /// disk, an update is about the banner in the window, and neither names a place to be put.
    var destination: NoticeDestination? {
        switch self {
        case .imageSaved(_, _, let fileName): .library(fileName: fileName)
        case .downloadFinished, .downloadFailed, .updateAvailable: nil
        }
    }
}
