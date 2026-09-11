import ZephraEngine
import ZephraLinkProtocol

/// Model transfers as rows on the phone.
///
/// The phone watches these and never starts one: a download is gigabytes onto somebody else's
/// Mac, and `Command` has no case for it on purpose.
public enum DownloadProjection {
    /// Every transfer this session knows about, in the order the Mac lists them.
    public static func downloads(_ downloads: [ModelDownload]) -> [DownloadDTO] {
        downloads.map(DownloadDTO.init)
    }
}
