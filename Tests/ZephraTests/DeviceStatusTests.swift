import Foundation
import Testing

@testable import Zephra

/// What the Devices list says under a phone's name.
@Suite("A paired device's line says whether it is here, when it was, or that it never has been")
struct DeviceStatusTests {
    @Test("a phone with a session up is connected, whatever the date says")
    func connectedWins() {
        #expect(DeviceStatus.of(connected: true, lastSeen: nil) == .connected)
        #expect(DeviceStatus.of(connected: true, lastSeen: .distantPast) == .connected)
    }

    @Test("a phone that has been here reads as last seen then")
    func seenCarriesTheDate() {
        let date = Date(timeIntervalSince1970: 1_757_000_000)
        #expect(DeviceStatus.of(connected: false, lastSeen: date) == .seen(date))
    }

    @Test("a phone that has never connected says so")
    func neverIsNever() {
        #expect(DeviceStatus.of(connected: false, lastSeen: nil) == .never)
    }
}
