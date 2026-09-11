import Foundation
import Network
import ZephraLinkProtocol

/// What a Mac publishes on the local network, and how a phone reads it back.
///
/// One place for the service type and the two TXT keys, because the listener writes them and
/// the browser reads them and a disagreement between the two is a Mac nobody can find. The room
/// is in the record so a phone that has paired already knows which of several Macs is its own
/// before it opens a connection to any of them: the room is the hash of the Mac's signing key,
/// so it identifies without naming.
public enum BonjourRecord {
    /// The service type both ends use.
    public static let type = "_zephra._tcp"
    /// The TXT key holding the relay room, which is what names the Mac.
    public static let roomKey = "room"
    /// The TXT key holding the protocol version, as a string because TXT records are text.
    public static let versionKey = "v"

    /// The record a listener publishes for one room.
    public static func txt(room: RoomID) -> NWTXTRecord {
        var record = NWTXTRecord()
        record[roomKey] = room.rawValue
        record[versionKey] = String(LinkProtocolVersion.current)
        return record
    }

    /// The room a browse result names, or nil where the record does not say.
    ///
    /// A missing room is not a failure: a Mac from a newer or older build still shows in the
    /// list, it just cannot be matched to a pairing without connecting to it.
    public static func room(in metadata: NWBrowser.Result.Metadata) -> RoomID? {
        guard case .bonjour(let record) = metadata, let value = record[roomKey], !value.isEmpty
        else { return nil }
        return RoomID(rawValue: value)
    }
}
