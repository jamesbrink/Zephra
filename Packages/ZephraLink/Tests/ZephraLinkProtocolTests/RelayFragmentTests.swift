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
