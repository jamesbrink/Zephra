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
    private var isOpen = false
    private var joined: RoomID?
    private var sends: [Int] = []

    /// The room the last good join asked for, which is what a test checks the signature bought.
    var joinedRoom: RoomID? { lock.withLock { joined } }

    /// The size in bytes of every `send` frame this relay was handed, in the order they came,
    /// which is how a test asks whether a large payload was cut up before it left.
    var sendFrameSizes: [Int] { lock.withLock { sends } }

    /// The allow-list this relay last heard, from the join or from an `allow` after it.
    var allowList: [Data]? { lock.withLock { allow } }

    /// Whether the host last said its room admits a guest on no list.
    var isRoomOpen: Bool { lock.withLock { isOpen } }

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
            self.answer(message, raw: content, on: connection)
            self.receive(on: connection)
        }
    }

    /// A `send` is echoed back as the very bytes it arrived as, which is what the deployed relay
    /// does — it forwards the frame verbatim, so a fragment's extra fields survive the trip.
    private func answer(_ message: RelayMessage, raw: Data, on connection: NWConnection) {
        switch message {
        case .hello:
            let fresh = Data((0..<RelayJoin.nonceByteCount).map { _ in UInt8.random(in: 0...255) })
            lock.withLock { nonce = fresh }
            send(.challenge(nonce: fresh), to: connection)
        case .join(let room, let publicKey, let role, let signature, let allow, _):
            lock.withLock {
                self.allow = allow
                isOpen = message.isOpen
            }
            send(verdict(room, publicKey, role, signature), to: connection)
        case .allow(let pubs, _):
            lock.withLock {
                allow = pubs
                isOpen = message.isOpen
            }
        case .send:
            lock.withLock { sends.append(raw.count) }
            send(raw, to: connection)
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
        lock.withLock { joined = room }
        return .joined(role: role)
    }

    private func send(_ message: RelayMessage, to connection: NWConnection) {
        guard let bytes = try? LinkJSON.encode(message) else { return }
        send(bytes, to: connection)
    }

    private func send(_ bytes: Data, to connection: NWConnection) {
        let context = NWConnection.ContentContext(
            identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
        connection.send(
            content: bytes, contentContext: context, isComplete: true,
            completion: .contentProcessed { _ in })
    }
}
