import Foundation
import Testing

@testable import Zephra

/// When a Mac that has lost the GPU relaunches itself, and when it waits to be asked.
///
/// Relaunching is the only remedy, and most of these Macs have nobody in front of them. The
/// guard is what keeps that from becoming a loop on a Mac whose GPU is genuinely broken: one
/// automatic relaunch in ten minutes, and after that the canvas's button is the whole offer.
@Suite("Relaunching after a lost GPU")
struct DeviceLossRelaunchTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("a Mac that has never done it relaunches after the sentence has been read")
    func firstLossRelaunches() {
        #expect(
            DeviceLossRelaunch.decide(lastRelaunch: nil, now: Self.now)
                == .relaunchAfter(.seconds(5)))
    }

    @Test("a second loss minutes after the first offers the button instead")
    func secondLossWithinTheWindowWaits() {
        let threeMinutesAgo = Self.now.addingTimeInterval(-3 * 60)
        #expect(
            DeviceLossRelaunch.decide(lastRelaunch: threeMinutesAgo, now: Self.now)
                == .offerButtonOnly)
    }

    @Test("past the window it is a fresh fault and the Mac comes back on its own again")
    func pastTheWindowRelaunches() {
        let elevenMinutesAgo = Self.now.addingTimeInterval(-11 * 60)
        #expect(
            DeviceLossRelaunch.decide(lastRelaunch: elevenMinutesAgo, now: Self.now)
                == .relaunchAfter(.seconds(5)))
    }

    @Test("a stamp in the future is read as recent rather than as a reason to loop")
    func aClockThatMovedBackwardsDoesNotLoop() {
        let tomorrow = Self.now.addingTimeInterval(24 * 60 * 60)
        #expect(
            DeviceLossRelaunch.decide(lastRelaunch: tomorrow, now: Self.now) == .offerButtonOnly)
    }

    @Test("the window is exactly ten minutes and the wait five seconds")
    func theTwoFigures() {
        #expect(DeviceLossRelaunch.guardWindow == 600)
        #expect(DeviceLossRelaunch.delay == .seconds(5))
        let tenMinutesAgo = Self.now.addingTimeInterval(-600)
        #expect(
            DeviceLossRelaunch.decide(lastRelaunch: tenMinutesAgo, now: Self.now)
                == .relaunchAfter(.seconds(5)), "the boundary itself is past the window")
    }
}
