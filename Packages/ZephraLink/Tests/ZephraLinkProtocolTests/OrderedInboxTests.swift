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

    @Test("A gap nothing fills is loss: the channel closes and the owner is told")
    func anUnfilledGapIsLoss() async throws {
        let (sender, receiver) = SecureChannelTests.channels()
        let inbox = OrderedInbox(channel: receiver, hold: .milliseconds(20))
        let told = Told()
        inbox.onLoss { told.say() }
        _ = try sender.seal(Self.frame("1"))
        #expect(try inbox.accept(try sender.seal(Self.frame("2"))).isEmpty)
        try await Task.sleep(for: .milliseconds(200))
        #expect(receiver.isClosed)
        #expect(told.wasTold)
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

/// Whether the inbox said a frame was lost, from whichever thread it said it on.
final class Told: @unchecked Sendable {
    private let lock = NSLock()
    private var told = false

    var wasTold: Bool { lock.withLock { told } }

    func say() { lock.withLock { told = true } }
}
