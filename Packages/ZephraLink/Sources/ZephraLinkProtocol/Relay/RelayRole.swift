/// Which end of a room a device is.
///
/// The relay keeps at most one of each per room and forwards between them. A role rather than a
/// free-for-all because a room is two devices by definition: a Mac and the phone talking to it.
public enum RelayRole: String, Codable, Hashable, Sendable, CaseIterable {
    /// The Mac, which the room is named after.
    case host
    /// The phone.
    case guest
}
