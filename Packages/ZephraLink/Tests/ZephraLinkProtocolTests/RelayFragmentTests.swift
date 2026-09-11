import Foundation
import Testing
import ZephraLinkProtocol

/// Cutting a payload down to what one WebSocket frame carries, and putting it back.
@Suite("A large relay payload is cut into slices and reassembled")
struct RelayFragmentTests {
    @Test("a payload that fits goes as one plain send with no fragment fields")
    func aSmallPayloadIsNotCut() throws {
        let payload = Data(repeating: 7, count: 1024)
        let messages = RelayFragment.messages(for: payload)
        #expect(messages == [.send(payload: payload)])
        #expect(
            String(decoding: try LinkJSON.encode(messages[0]), as: UTF8.self)
                == #"{"a":"send","d":"\#(payload.base64EncodedString())"}"#)
    }

    @Test("a 64 KiB chunk is cut into slices of at most 24,000 characters of base64")
    func aBlobChunkIsCut() throws {
        // The size that killed the socket: a 64 KiB chunk sealed and base64'd is about 87 KB,
        // and API Gateway allows 32 KB in one frame.
        let payload = Data((0..<(64 * 1024 + 33)).map { UInt8($0 % 251) })
        let messages = RelayFragment.messages(for: payload)
        #expect(messages.count == 4)
        var ids: Set<String> = []
        for (index, message) in messages.enumerated() {
            guard case .send(let slice, let id, let at, let count) = message else {
                Issue.record("a slice is not a send")
                return
            }
            #expect(slice.base64EncodedString().count <= RelayFragment.base64Limit)
            #expect(at == index)
            #expect(count == messages.count)
            #expect(id?.count == RelayFragment.idLength)
            #expect(id?.allSatisfy { $0.isHexDigit && !$0.isUppercase } == true)
            ids.insert(id ?? "")
        }
        #expect(ids.count == 1, "every slice of one payload shares one message id")
    }

    @Test("a slice is the JSON the relay's contract spells out")
    func aSliceIsTheAgreedJSON() throws {
        let message = RelayMessage.send(
            payload: Data([0xAB]), message: "0123456789abcdef", index: 1, count: 3)
        #expect(
            String(decoding: try LinkJSON.encode(message), as: UTF8.self)
                == #"{"a":"send","d":"qw==","i":1,"m":"0123456789abcdef","n":3}"#)
        #expect(
            try LinkJSON.decode(
                RelayMessage.self,
                from: Data(#"{"a":"send","d":"qw==","i":1,"m":"0123456789abcdef","n":3}"#.utf8))
                == message)
    }

    @Test("slices that arrive out of order are released as one whole payload")
    func slicesAreReassembledOutOfOrder() {
        let payload = Data((0..<50_000).map { UInt8($0 % 251) })
        let messages = RelayFragment.messages(for: payload)
        let inbox = RelayFragments()
        // The relay's invocations run concurrently, so the last slice can land first.
        #expect(inbox.accept(messages[2]) == nil)
        #expect(inbox.accept(messages[0]) == nil)
        #expect(inbox.accept(messages[1]) == payload)
        #expect(inbox.heldSets == 0)
    }

    @Test("an unfragmented send passes straight through")
    func anUnfragmentedSendPassesThrough() {
        let inbox = RelayFragments()
        #expect(inbox.accept(.send(payload: Data("sealed".utf8))) == Data("sealed".utf8))
        #expect(inbox.accept(.ping) == nil)
    }

    @Test("a set nothing finishes is dropped once its life runs out")
    func anUnfinishedSetIsDropped() async throws {
        let inbox = RelayFragments(lifetime: .milliseconds(20))
        let messages = RelayFragment.messages(for: Data(repeating: 3, count: 40_000))
        #expect(inbox.accept(messages[0]) == nil)
        #expect(inbox.heldSets == 1)
        try await Task.sleep(for: .milliseconds(40))
        // The stale set goes as the next slice lands, and the one that lands is all that is left.
        #expect(inbox.accept(messages[1]) == nil)
        #expect(inbox.heldSets == 1)
        #expect(inbox.accept(messages[0]) == nil, "the set it belonged to is gone")
    }

    @Test("only so many unfinished sets are held at once")
    func theNumberOfSetsIsCapped() {
        let inbox = RelayFragments(setLimit: 2)
        for id in ["a", "b", "c", "d"] {
            _ = inbox.accept(.send(payload: Data([1]), message: id, index: 0, count: 2))
        }
        #expect(inbox.heldSets == 2)
    }

    @Test("slices of forty messages interleaved round robin all reassemble")
    func manyMessagesInterleaveWithoutLoss() {
        // What the live run did: a picture transfer's chunks are six slices each and the relay's
        // invocations post them concurrently, so far more than the old cap of eight `m` sets are
        // open at once. Round robin is the worst arrangement of that — every set is one slice
        // short until the very last pass.
        let inbox = RelayFragments()
        let payloads = (0..<40).map { message in
            Data((0..<(5 * RelayFragment.byteLimit + 11)).map { UInt8(($0 + message) % 251) })
        }
        let messages = payloads.enumerated().map { message, payload in
            RelayFragment.messages(for: payload, id: String(format: "%016x", message))
        }
        #expect(messages.allSatisfy { $0.count == 6 })
        var whole: [Int: Data] = [:]
        for slice in 0..<6 {
            for (message, slices) in messages.enumerated() {
                if let payload = inbox.accept(slices[slice]) { whole[message] = payload }
            }
        }
        #expect(whole.count == 40)
        for (message, payload) in whole { #expect(payload == payloads[message]) }
        #expect(inbox.heldSets == 0)
        #expect(inbox.heldBytes == 0)
    }

    @Test("a set past its life goes before the cap has to evict anything")
    func expiryIsTriedBeforeTheCap() async throws {
        let inbox = RelayFragments(lifetime: .milliseconds(20), setLimit: 2)
        _ = inbox.accept(.send(payload: Data([1]), message: "stale", index: 0, count: 2))
        _ = inbox.accept(.send(payload: Data([2]), message: "also-stale", index: 0, count: 2))
        try await Task.sleep(for: .milliseconds(40))
        // Two fresh sets land over a cap of two, and both stand: what went was the stale pair.
        _ = inbox.accept(.send(payload: Data([3]), message: "fresh", index: 0, count: 2))
        _ = inbox.accept(.send(payload: Data([4]), message: "fresher", index: 0, count: 2))
        #expect(inbox.heldSets == 2)
        #expect(inbox.accept(.send(payload: Data([3]), message: "fresh", index: 1, count: 2)) != nil)
        #expect(inbox.accept(.send(payload: Data([1]), message: "stale", index: 1, count: 2)) == nil)
    }

    @Test("the bytes held across every set are capped, oldest first")
    func theBytesHeldAreCapped() {
        // A count is not a memory bound: the cap that matters is what the sets weigh together.
        let slice = Data(repeating: 9, count: 1_000)
        let inbox = RelayFragments(setLimit: 1_000, byteLimit: 3_000)
        for message in 0..<5 {
            _ = inbox.accept(
                .send(payload: slice, message: "m\(message)", index: 0, count: 2))
        }
        #expect(inbox.heldSets == 3)
        #expect(inbox.heldBytes == 3_000)
        // The three that stand are the newest; the first two went as the bytes passed the cap.
        #expect(inbox.accept(.send(payload: slice, message: "m0", index: 1, count: 2)) == nil)
        #expect(inbox.accept(.send(payload: slice, message: "m4", index: 1, count: 2)) != nil)
    }

    @Test("a slice that names an impossible index or count is dropped")
    func anImpossibleSliceIsDropped() {
        let inbox = RelayFragments()
        #expect(inbox.accept(.send(payload: Data([1]), message: "a", index: 3, count: 2)) == nil)
        #expect(inbox.accept(.send(payload: Data([1]), message: "a", index: -1, count: 2)) == nil)
        #expect(inbox.accept(.send(payload: Data([1]), message: "a", index: 0, count: 0)) == nil)
        #expect(
            inbox.accept(
                .send(
                    payload: Data([1]), message: "a", index: 0,
                    count: RelayFragment.sliceLimit + 1)) == nil)
        #expect(inbox.heldSets == 0)
    }
}
