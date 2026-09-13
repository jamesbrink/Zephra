import Foundation
import Testing
import ZephraCore
import ZephraLinkClient
import ZephraLinkHost
import ZephraLinkProtocol
import ZephraLinkTransport
@testable import ZephraEngine

/// Each host has independent temporary storage, keys and a mock backend; phones use real clients.
@MainActor
final class LiveMultiHostRun {
    let phones = [DeviceIdentity(), DeviceIdentity()]
    var beds: [CompanionTestBed] = []
    var clients: [[LinkClient]] = []
    var relays: [RelayListener] = []
    let cadence = [RelayCadence(messagesPerSecond: 120, burst: 40), RelayCadence(messagesPerSecond: 120, burst: 40)]
    let admissions = [TransferAdmission(), TransferAdmission()]
    let budgets = [BlobBudget(), BlobBudget()]
    let relayURL = URL(string: "wss://zephra-link.urandom.io")!

    func start(count: Int, relay: Bool) async throws {
        for number in 0..<count {
            let bed = CompanionTestBed(hostName: "Qualification Mac \(number)")
            beds.append(bed)
            log("starting host \(number)")
            await bed.bootstrap()
            bed.store.availability[bed.store.descriptor.id] = .available
            let picture = try bed.engine.library.write(LibraryAnnotationTests.image(seed: UInt64(number)))
            try FileManager.default.moveItem(at: picture, to: bed.engine.directory.appending(path: "same.png"))
            await bed.index.rescanNow()
            var endpoint: Endpoint?
            if relay {
                let listener = RelayListener(url: relayURL, identity: bed.identity)
                relays.append(listener)
                await listener.updateAllowList(phones.map { $0.publicKeys.signing }, open: true)
                try await listener.start()
                bed.host.serve(listener)
            } else {
                let listener = try TCPListener()
                bed.host.serve(listener)
                endpoint = Endpoint(host: "127.0.0.1", port: try await listener.start())
            }
            var connections: [LinkClient] = []
            clients.append([])
            for index in phones.indices {
                let network = NetworkLinkRoads(relayURL: relayURL, identity: phones[index], cadence: cadence[index])
                let client = LinkClient(store: MemoryLinkKeyStore(identity: phones[index]),
                    roads: LiveQualificationRoads(endpoint: endpoint, network: network),
                    deviceName: "Qualification Phone \(index)", transferAdmission: admissions[index], blobBudget: budgets[index])
                connections.append(client)
                clients[number] = connections
                log("pairing host \(number) phone \(index)")
                try await client.pair(with: bed.host.beginPairing())
                try await wait { client.supportsMultiHost && client.libraryIsComplete }
                #expect(client.connection == .live(relay ? .relay : .lan))
                #expect(client.hostID == HostID(keys: bed.keys))
                try await client.setPreviews(index == 0)
            }
            if relay { await relays[number].updateAllowList(bed.host.relayAllowList, open: false) }
        }
    }

    func exercise() async throws {
        for index in beds.indices {
            let bed = beds[index]
            log("exercising host \(index)")
            let client = clients[index][0], other = clients[index][1]
            var settings = bed.store.descriptor.capabilities.clamp(bed.store.settings)
            settings.prompt = "qualification host \(index)"
            let job = StrictGeneration(request: GenerationRequest(modelID: bed.store.descriptor.id, count: 1, settings: settings))
            #expect(try await client.offer(job).refusal == nil)
            // The same request UUID from different authenticated phones is two independent jobs.
            log("submitting on host \(index)")
            async let left = client.submit(job, reference: nil)
            async let right = other.submit(job, reference: nil)
            let (one, two) = try await (left, right)
            #expect(one.batchID != two.batchID)
            try await wait { bed.store.running == nil && bed.store.queue.isEmpty && bed.store.pendingOutputBatches.isEmpty }
            let before = bed.store.history.count
            log("reconnecting host \(index)")
            await client.disconnect()
            #expect(other.connection.isLive)
            log("checking other phone receipt on host \(index)")
            #expect(try await other.receipt(job.request.requestID).batchID == two.batchID)
            log("connecting first phone on host \(index)")
            await client.connect()
            try await wait { client.supportsMultiHost && client.connection.isLive }
            log("retrying first receipt on host \(index)")
            #expect(try await client.submit(job, reference: nil).batchID == one.batchID)
            #expect(bed.store.history.count == before, "reconnect replay cannot create work")
            #expect(bed.host.devices.count == 2)
            try await client.setTags(names: ["same.png"], tags: ["owner-\(index)"])
            await bed.index.settle()
            let source = bed.engine.directory.appending(path: "same.png")
            #expect(bed.engine.library.annotation(at: source).tags == ["owner-\(index)"])
            // A valid PNG with harmless trailing data forces fragmented bulk traffic.
            var bytes = try Data(contentsOf: source)
            bytes.append(Data(repeating: UInt8(index), count: 1_048_576))
            try bytes.write(to: source)
            log("downloading host \(index)")
            async let firstFile = client.file(name: "same.png")
            async let secondFile = other.file(name: "same.png")
            let files = try await (firstFile, secondFile)
            #expect(files.0 == bytes && files.1 == bytes)
            for prior in beds.indices where prior != index {
                let tags = beds[prior].engine.library.annotation(at: beds[prior].engine.directory.appending(path: "same.png")).tags
                #expect(!tags.contains("owner-\(index)"), "mutations cannot cross rooms")
            }
        }
        if beds.count > 1 {
            await beds[0].host.stop()
            try await wait { !clients[0][0].connection.isLive && !clients[0][1].connection.isLive }
            for row in clients.dropFirst() {
                #expect(row.allSatisfy { $0.connection.isLive })
                #expect(try await row[0].libraryPage(offset: 0, limit: 10).entries.count > 0)
            }
        }
    }

    func log(_ message: String) {
        let line = Data("MULTI_HOST_UAT \(Date().ISO8601Format()) \(message)\n".utf8)
        FileHandle.standardError.write(line)
        if let path = ProcessInfo.processInfo.environment["ZEPHRA_UAT_LOG_PATH"] {
            if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
            if let file = FileHandle(forWritingAtPath: path) {
                defer { try? file.close() }
                _ = try? file.seekToEnd(); try? file.write(contentsOf: line)
            }
        }
    }
    func stop() async {
        for row in clients { for client in row { await client.disconnect() } }
        for bed in beds { await bed.shutdown() }
    }
    func wait(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(30)
        while !condition() {
            guard ContinuousClock.now < deadline else { throw LinkClientError.unreachable }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
