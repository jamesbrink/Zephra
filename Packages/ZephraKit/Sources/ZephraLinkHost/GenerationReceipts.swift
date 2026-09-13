import Foundation
import ZephraLinkProtocol

/// Durable write-ahead receipts. Prepared/unknown records are never replayed automatically.
@MainActor
public final class GenerationReceipts {
    var records: [String: GenerationReceipt] = [:]
    let root: URL?
    private var failure: (any Error)?
    let persist: @MainActor (Data, URL) throws -> Void
    public init(root: URL? = nil, persist: @escaping @MainActor (Data, URL) throws -> Void = {
        try $0.write(to: $1, options: .atomic)
    }) {
        self.root = root
        self.persist = persist
        guard let root else { return }
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            where url.pathExtension == "json" {
                var receipt = try LinkJSON.decode(GenerationReceipt.self, from: Data(contentsOf: url))
                // A previous process's volatile queue cannot establish completion or absence.
                if receipt.status == .accepted { receipt.status = .unknown }
                records[url.deletingPathExtension().lastPathComponent] = receipt
            }
        } catch { failure = error }
    }
    public func read(peer: DevicePublicKeys, request: UUID) throws -> GenerationReceipt? {
        if let failure { throw failure }
        return records[key(peer, request)]
    }
    public func write(_ receipt: GenerationReceipt, peer: DevicePublicKeys) throws {
        if let failure { throw failure }
        let key = key(peer, receipt.requestID)
        if let root {
            try persist(LinkJSON.encode(receipt), root.appendingPathComponent(key + ".json"))
        }
        records[key] = receipt
    }
    private func key(_ peer: DevicePublicKeys, _ request: UUID) -> String {
        HostID(keys: peer).rawValue + "-" + request.uuidString
    }
}
