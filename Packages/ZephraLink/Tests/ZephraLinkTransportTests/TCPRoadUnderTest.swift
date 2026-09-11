import Foundation
import Network
import Testing

@testable import ZephraLinkTransport

/// A listener on a port the system picked, a client connected to it, and the connection it
/// accepted: the smallest real socket a frame can be made to cross.
final class TCPRoadUnderTest {
    let listener: TCPListener
    let client: TCPConnection
    let server: TCPConnection
    private let fromClient: FrameReader
    private let fromServer: FrameReader

    /// Stands the road up and waits until both ends are connected.
    init() async throws {
        listener = try TCPListener()
        let port = try await listener.start()
        client = TCPConnection(host: "127.0.0.1", port: port)
        try await client.start()
        var connections = listener.connections().makeAsyncIterator()
        let accepted = await connections.next()
        server = try #require(accepted as? TCPConnection)
        fromClient = FrameReader(client.frames())
        fromServer = FrameReader(server.frames())
    }

    /// The next frame the server read, or nil when its stream finished.
    func nextFromServer() async throws -> Data? { try await fromServer.next() }

    /// The next frame the client read, or nil when its stream finished.
    func nextFromClient() async throws -> Data? { try await fromClient.next() }

    /// A length prefix with no body behind it, for the frames no honest end would send.
    func sendRawPrefix(_ length: UInt32) async throws {
        var bytes = Data()
        withUnsafeBytes(of: length.bigEndian) { bytes.append(contentsOf: $0) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            client.connection.send(
                content: bytes,
                completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
        }
    }

    /// Closes everything, whatever the test did.
    func tearDown() {
        Task { [client, server, listener] in
            await client.close()
            await server.close()
            await listener.stop()
        }
    }
}

/// One stream of frames, read from one place.
///
/// An `AsyncThrowingStream`'s iterator is a struct and a suite wants to read a frame here and a
/// frame there, so it lives in a box rather than in a `for await` that would own the whole test.
final class FrameReader {
    private var iterator: AsyncThrowingStream<Data, Error>.Iterator

    init(_ stream: AsyncThrowingStream<Data, Error>) {
        iterator = stream.makeAsyncIterator()
    }

    func next() async throws -> Data? { try await iterator.next() }
}
