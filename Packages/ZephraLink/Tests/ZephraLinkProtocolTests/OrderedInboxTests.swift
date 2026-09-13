import CryptoKit
import Foundation
import Testing
@testable import ZephraLinkProtocol

@Suite("The inbox puts a reordered stream back in the order it was sealed in")
struct OrderedInboxTests {
    /// A sender, and an inbox over the channel facing it.
    static func pair(hold: Duration = .milliseconds(50)) -> (SecureChannel, OrderedInbox) {
        let (sender, receiver) = SecureChannelTests.channels()
        return (sender, OrderedInbox(channel: receiver, hold: hold))
    }

    /// One envelope naming itself, so a released frame says which it was.
    static func frame(_ name: String) -> Frame {
        .envelope(Envelope(kind: .delta, body: Data(#"{"n":"\#(name)"}"#.utf8)))
    }

    /// What an envelope frame's body says.
    static func name(of frame: Frame) -> String? {
        guard case .envelope(let envelope) = frame else { return nil }
        return String(decoding: envelope.body, as: UTF8.self)
    }

    @Test("Frames handed over as 1, 3, 2, 4 are released as 1, 2, 3, 4")
    func reorderedFramesAreReleasedInOrder() throws {
        let (sender, inbox) = Self.pair()
        let sealed = try (1...4).map { try sender.seal(Self.frame("\($0)")) }
        var released: [String] = []
        for index in [0, 2, 1, 3] {
            released += try inbox.accept(sealed[index]).compactMap(Self.name)
        }
        #expect(released == [#"{"n":"1"}"#, #"{"n":"2"}"#, #"{"n":"3"}"#, #"{"n":"4"}"#])
    }

    @Test("A frame held for a gap is released the moment the gap fills")
    func aHeldFrameWaitsForTheOneBeforeIt() throws {
        let (sender, inbox) = Self.pair()
        let first = try sender.seal(Self.frame("1"))
        let second = try sender.seal(Self.frame("2"))
        #expect(try inbox.accept(second).isEmpty, "nothing may be released over a gap")
        #expect(try inbox.accept(first).count == 2)
    }

    @Test("A duplicate is dropped and the channel stays open")
    func aDuplicateIsDropped() throws {
        let (sender, inbox) = Self.pair()
        let sealed = try sender.seal(Self.frame("1"))
        #expect(try inbox.accept(sealed).count == 1)
        #expect(throws: SecureChannelError.replayed) { try inbox.accept(sealed) }
        #expect(try inbox.accept(try sender.seal(Self.frame("2"))).count == 1)
    }

    @Test("A frame two thousand ahead is refused")
    func aFrameFarAheadIsRefused() throws {
        let (sender, inbox) = Self.pair()
        for _ in 0..<2000 { _ = try sender.seal(Self.frame("filler")) }
        #expect(throws: SecureChannelError.outOfWindow) {
            try inbox.accept(try sender.seal(Self.frame("far")))
        }
    }

    @Test("A tampered frame still closes the channel")
    func tamperingStillCloses() throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(50))
        var sealed = try sender.seal(Self.frame("1"))
        sealed[sealed.count - 1] ^= 0x01
        #expect(throws: SecureChannelError.undecipherable) { try inbox.accept(sealed) }
        #expect(receiver.isClosed)
    }

    @Test("A gap nothing fills is skipped: the held frames come out and the channel stays open")
    func anUnfilledGapIsSkipped() async throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(20))
        let told = ToldTheGap()
        inbox.onGap { told.say($0, $1) }
        _ = try sender.seal(Self.frame("the one that never comes"))
        let rest = try (3...5).map { try sender.seal(Self.frame("\($0)")) }
        for bytes in rest { #expect(try inbox.accept(bytes).isEmpty) }
        let deadline = ContinuousClock.now + .seconds(2)
        while told.gap == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }

        #expect(!receiver.isClosed, "one hole is a message lost, not a session")
        #expect(
            told.frames.compactMap(Self.name)
                == [#"{"n":"3"}"#, #"{"n":"4"}"#, #"{"n":"5"}"#],
            "everything waiting behind the hole is released, in order")
        #expect(told.gap?.expected == 0)
        #expect(told.gap?.nextHeld == 1)
        #expect(told.gap?.held == 3)
    }

    @Test("The stream carries on past a skip, and the frame it stepped over is replayed")
    func theStreamCarriesOnPastASkip() async throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(20))
        let told = ToldTheGap()
        inbox.onGap { told.say($0, $1) }
        let missing = try sender.seal(Self.frame("the one that never comes"))
        #expect(try inbox.accept(try sender.seal(Self.frame("2"))).isEmpty)
        let deadline = ContinuousClock.now + .seconds(2)
        while told.gap == nil && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }

        #expect(try inbox.accept(try sender.seal(Self.frame("3"))).count == 1, "the next lands")
        #expect(
            throws: SecureChannelError.replayed,
            "the release point jumped, so the hole's own frame is behind the stream now"
        ) { try inbox.accept(missing) }
        #expect(told.count == 1, "one skip, one word about it")
    }

    @Test("A gap that fills leaves no clock running against the gap after it")
    func theHoldIsMeasuredPerGap() async throws {
        // Sustained reordering: something is always waiting, so the stream never empties, and
        // each gap fills long before the hold runs out. A clock armed once and left running would
        // reach the end of its half-second with a gap that was milliseconds old open, and step
        // over a frame that was on its way.
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(100))
        let told = ToldTheGap()
        inbox.onGap { told.say($0, $1) }
        let sealed = try (0...4).map { try sender.seal(Self.frame("\($0)")) }

        var released: [String] = []
        released += try inbox.accept(sealed[2]).compactMap(Self.name)
        released += try inbox.accept(sealed[4]).compactMap(Self.name)
        try await Task.sleep(for: .milliseconds(50))
        released += try inbox.accept(sealed[0]).compactMap(Self.name)
        try await Task.sleep(for: .milliseconds(20))
        released += try inbox.accept(sealed[1]).compactMap(Self.name)
        // Past where a clock armed at the first gap would have run out, and not past where one
        // armed at the gap that is actually open will.
        try await Task.sleep(for: .milliseconds(40))

        #expect(told.count == 0, "no gap here was ever older than the hold")
        released += try inbox.accept(sealed[3]).compactMap(Self.name)
        #expect(
            released == (0...4).map { #"{"n":"\#($0)"}"# },
            "every frame comes out, in order, with nothing stepped over")
        #expect(!receiver.isClosed)
    }

    @Test("More held frames than the limit is loss too")
    func tooManyHeldFramesIsLoss() throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .seconds(60), frameLimit: 4)
        _ = try sender.seal(Self.frame("the one that never comes"))
        var sealed: [Data] = []
        for index in 0..<6 { sealed.append(try sender.seal(Self.frame("\(index)"))) }
        #expect(throws: SecureChannelError.lost) {
            for bytes in sealed { _ = try inbox.accept(bytes) }
        }
        #expect(receiver.isClosed)
    }

    @Test("A gap that fills in time leaves the channel alone")
    func aGapFilledInTimeIsNotLoss() async throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(200))
        let first = try sender.seal(Self.frame("1"))
        _ = try inbox.accept(try sender.seal(Self.frame("2")))
        #expect(try inbox.accept(first).count == 2)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!receiver.isClosed)
    }
}

/// What the inbox said about a skip, from whichever thread it said it on: the gap, the frames it
/// released, and how many skips there have been.
final class ToldTheGap: @unchecked Sendable {
    private let lock = NSLock()
    private var told: FrameGap?
    private var released: [Frame] = []
    private var skips = 0

    var gap: FrameGap? { lock.withLock { told } }

    var frames: [Frame] { lock.withLock { released } }

    var count: Int { lock.withLock { skips } }

    func say(_ gap: FrameGap, _ frames: [Frame]) {
        lock.withLock {
            told = gap
            released += frames
            skips += 1
        }
    }
}
