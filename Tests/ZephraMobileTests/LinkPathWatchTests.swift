import Foundation
import Testing

@testable import ZephraMobile

/// What the phone does when the network under it changes.
///
/// The decision alone: `NWPathMonitor` is the system's and cannot be made to report anything
/// in a test, so the reporting is exercised by hand on a phone and the answer to a report is
/// pinned here.
@Suite("A change of network path is worth one thing or nothing")
struct LinkPathWatchTests {
    private let wifi = LinkPathMark(
        isSatisfied: true, isExpensive: false, isConstrained: false, interfaces: ["en0"])
    private let cellular = LinkPathMark(
        isSatisfied: true, isExpensive: true, isConstrained: false, interfaces: ["pdp_ip0"])
    private let nothing = LinkPathMark(
        isSatisfied: false, isExpensive: false, isConstrained: false, interfaces: [])

    @Test("the first path the system reports is nothing to act on")
    func firstReportDoesNothing() {
        #expect(LinkPathWatch.reaction(from: nil, to: wifi, isLive: false) == .nothing)
        #expect(LinkPathWatch.reaction(from: nil, to: wifi, isLive: true) == .nothing)
    }

    @Test("the same path again is nothing to act on")
    func anUnchangedPathDoesNothing() {
        #expect(LinkPathWatch.reaction(from: wifi, to: wifi, isLive: false) == .nothing)
        #expect(LinkPathWatch.reaction(from: wifi, to: wifi, isLive: true) == .nothing)
    }

    @Test("a path that carries nothing is nothing to act on either")
    func losingThePathDoesNothing() {
        #expect(LinkPathWatch.reaction(from: wifi, to: nothing, isLive: true) == .nothing)
        #expect(LinkPathWatch.reaction(from: wifi, to: nothing, isLive: false) == .nothing)
    }

    @Test("a new path with nothing connected dials at once rather than waiting it out")
    func aNewPathRedials() {
        #expect(LinkPathWatch.reaction(from: nothing, to: wifi, isLive: false) == .redial)
        #expect(LinkPathWatch.reaction(from: wifi, to: cellular, isLive: false) == .redial)
    }

    @Test("a new path under a live session asks the Mac whether it is still there")
    func aNewPathUnderASessionProbes() {
        #expect(LinkPathWatch.reaction(from: wifi, to: cellular, isLive: true) == .probe)
    }

    @Test("a handover is several reports and one dial")
    func aFlappingPathActsOnce() {
        let now = Date(timeIntervalSince1970: 1_789_040_400)
        // The system says the path went, then that it is back over something else, then that it
        // has settled, inside a second. Acting on each is a dial that cancels the one before it.
        #expect(
            LinkPathWatch.reaction(
                from: nothing, to: cellular, isLive: false, lastAction: nil, now: now) == .redial)
        #expect(
            LinkPathWatch.reaction(
                from: cellular, to: wifi, isLive: false, lastAction: now,
                now: now.addingTimeInterval(0.4)) == .nothing)
        #expect(
            LinkPathWatch.reaction(
                from: cellular, to: wifi, isLive: true, lastAction: now,
                now: now.addingTimeInterval(0.4)) == .nothing)
        // Past the damping, a change is a change again.
        #expect(
            LinkPathWatch.reaction(
                from: cellular, to: wifi, isLive: false, lastAction: now,
                now: now.addingTimeInterval(1.2)) == .redial)
    }

    @Test("Wi-Fi giving way to cellular is a change, whatever else the two share")
    func theOrderOfTheInterfacesIsTheChange() {
        let home = LinkPathMark(
            isSatisfied: true, isExpensive: false, isConstrained: false,
            interfaces: ["en0", "pdp_ip0"])
        let away = LinkPathMark(
            isSatisfied: true, isExpensive: true, isConstrained: false,
            interfaces: ["pdp_ip0", "en0"])
        #expect(home != away)
        #expect(LinkPathWatch.reaction(from: home, to: away, isLive: true) == .probe)
    }
}
