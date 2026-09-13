import Foundation

/// What the Devices list says under a phone's name: that it is here, when it last was, or that
/// it never has been. Pure, so the words are pinned without a window.
enum DeviceStatus: Equatable {
    case connected
    case seen(Date)
    case never

    /// The status for one device, from whether it has a session up and when it was last seen.
    static func of(connected: Bool, lastSeen: Date?) -> DeviceStatus {
        if connected { return .connected }
        guard let lastSeen else { return .never }
        return .seen(lastSeen)
    }
}
