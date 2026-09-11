import Foundation
import Network
import ZephraLinkProtocol

/// A relay, in the process, for as long as one test needs one.
///
/// `NWListener` hosts the WebSocket and `URLSessionWebSocketTask` connects to it, which is the
/// same pair of frameworks the deployed relay and the app use, so the sequence under test is
/// the real one: hello, a challenge of thirty-two random bytes, a join whose Ed25519 signature
/// this verifies with `RelayJoin.verify`, then `joined`. A `send` is echoed back, which is what
/// a room with the other end already in it looks like.
final class FakeRelay: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "io.zephra.test.relay")
    private let lock = NSLock()
    private var client: NWConnection?
    private var nonce = Data()
    private let refusal: String?
    private var allow: [Data]?
    /// The room the last good join asked for, which is what a test checks the signature bought.
    private(set) var joinedRoom: RoomID?

    /// The allow-list this relay last heard, from the join or from an `allow` after it.
    var allowList: [Data]? { lock.withLock { allow } }

    /// A relay that lets a well-signed join in, or one that refuses every join with `refusing`.
    init(refusing: String? = nil) throws {
        refusal = refusing
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
        listener = try NWListener(using: parameters, on: .any)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
    }

    /// Starts it and answers the URL to connect to.
    func start() async throws -> URL {
        listener.start(queue: queue)
        while (listener.port?.rawValue ?? 0) == 0 { try await Task.sleep(for: .milliseconds(5)) }
        return URL(string: "ws://127.0.0.1:\(listener.port!.rawValue)")!
    }

    /// Stops it.
    func stop() {
        lock.withLock { client }?.cancel()
        listener.cancel()
    }

    /// Says something to the client out of turn, as a relay does when the other end moves.
    func push(_ message: RelayMessage) {
        guard let client = lock.withLock({ self.client }) else { return }
        send(message, to: client)
    }

    private func accept(_ connection: NWConnection) {
        lock.withLock { client = connection }
        connection.start(queue: queue)
        receive(on: connection)
    }

    private func receive(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self, error == nil, let content,
                let message = try? LinkJSON.decode(RelayMessage.self, from: content)
            else { return }
            self.answer(message, on: connection)
            self.receive(on: connection)
        }
    }

    private func answer(_ message: RelayMessage, on connection: NWConnection) {
        switch message {
        case .hello:
            let fresh = Data((0..<RelayJoin.nonceByteCount).map { _ in UInt8.random(in: 0...255) })
            lock.withLock { nonce = fresh }
            send(.challenge(nonce: fresh), to: connection)
        case .join(let room, let publicKey, let role, let signature, let allow):
            lock.withLock { self.allow = allow }
            send(verdict(room, publicKey, role, signature), to: connection)
        case .allow(let pubs):
            lock.withLock { allow = pubs }
        case .send(let payload):
            send(.send(payload: payload), to: connection)
        case .ping:
            send(.pong, to: connection)
        default:
            break
        }
    }

    /// What a join earns: the relay's own checks, in the relay's own words.
    private func verdict(
        _ room: RoomID, _ publicKey: Data, _ role: RelayRole, _ signature: Data
    ) -> RelayMessage {
        if let refusal { return .error(reason: refusal) }
        let challenge = lock.withLock { nonce }
        guard !challenge.isEmpty else { return .error(reason: "no challenge") }
        guard RelayJoin.verify(
            publicKey: publicKey, nonce: challenge, room: room, role: role, signature: signature)
        else { return .error(reason: "bad signature") }
        guard role == .guest || RoomID(signingPublicKey: publicKey) == room else {
            return .error(reason: "room does not match key")
        }
        lock.withLock { joinedRoom = room }
        return .joined(role: role)
    }

    private func send(_ message: RelayMessage, to connection: NWConnection) {
        guard let bytes = try? LinkJSON.encode(message) else { return }
        let context = NWConnection.ContentContext(
            identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(
            content: bytes, contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in })
    }
}
