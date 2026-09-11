import Foundation
import Testing
import ZephraLinkProtocol

@testable import ZephraLinkTransport

/// A frame crosses a real socket whole, in both directions, whatever its size.
@Suite("A TCP road carries whole frames")
struct TCPConnectionTests {
    @Test("a frame sent from either end arrives whole")
    func roundTrip() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        try await road.client.send(Data("hello".utf8))
        #expect(try await road.nextFromServer() == Data("hello".utf8))
        try await road.server.send(Data("there".utf8))
        #expect(try await road.nextFromClient() == Data("there".utf8))
    }

    @Test("a frame far larger than one packet arrives in one piece")
    func largeFrame() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        let payload = Data((0..<300_000).map { UInt8($0 % 251) })
        try await road.client.send(payload)
        #expect(try await road.nextFromServer() == payload)
    }

    @Test("an empty frame is a frame, not the end of the road")
    func emptyFrame() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        try await road.client.send(Data())
        #expect(try await road.nextFromServer() == Data())
        try await road.client.send(Data("after".utf8))
        #expect(try await road.nextFromServer() == Data("after".utf8))
    }

    @Test("a frame past the cap is refused before it is sent")
    func oversizeRefused() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        await #expect(throws: TCPConnectionError.frameTooLarge) {
            try await road.client.send(Data(count: TCPConnection.maxFrameBytes + 1))
        }
    }

    @Test("a length past the cap closes the road rather than allocating it")
    func oversizeLengthClosesTheRoad() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        try await road.sendRawPrefix(UInt32(TCPConnection.maxFrameBytes + 1))
        await #expect(throws: TCPConnectionError.frameTooLarge) {
            _ = try await road.nextFromServer()
        }
    }

    @Test("closing one end finishes the other's stream")
    func closeFinishesTheStream() async throws {
        let road = try await TCPRoadUnderTest()
        defer { road.tearDown() }
        try await road.client.send(Data("last".utf8))
        #expect(try await road.nextFromServer() == Data("last".utf8))
        await road.client.close()
        #expect(try await road.nextFromServer() == nil)
    }
}
