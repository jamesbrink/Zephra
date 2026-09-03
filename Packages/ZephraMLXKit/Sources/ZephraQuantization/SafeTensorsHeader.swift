import Foundation

/// The index at the front of a safetensors file: what is in it, and where.
///
/// The quantizer needs two things a tensor dictionary cannot give it. It needs to walk a shard
/// in the order the bytes are laid out, so a memory-mapped file is read once from front to back
/// instead of seeking about; and it needs each tensor's shape before deciding what to do with
/// it. Both come from the header alone, which is a few kilobytes, so neither costs a read of the
/// weights.
///
/// The format: eight little-endian bytes giving the length of a JSON header, then that header.
/// Every key but `__metadata__` names a tensor.
public struct SafeTensorsHeader: Sendable {
    /// One tensor's entry, without its bytes.
    public struct Entry: Hashable, Sendable {
        /// The tensor's key.
        public let name: String
        /// Its dimensions, outermost first.
        public let shape: [Int]
        /// Where its bytes start, relative to the end of the header.
        public let dataOffset: Int
    }

    /// Every tensor in the file, in the order its bytes appear.
    public let entries: [Entry]

    /// Reads the header of the safetensors file at `url`.
    ///
    /// Only the header is read: the file is mapped, and the mapping is dropped before this
    /// returns.
    public init(contentsOf url: URL) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let lengthBytes = try handle.read(upToCount: 8), lengthBytes.count == 8 else {
            throw QuantizationError.unreadableShard(url, reason: "no header length")
        }
        let length = lengthBytes.reversed().reduce(into: UInt64(0)) { total, byte in
            total = total << 8 | UInt64(byte)
        }
        guard length > 0, length < 100_000_000,
            let headerBytes = try handle.read(upToCount: Int(length)),
            headerBytes.count == Int(length)
        else {
            throw QuantizationError.unreadableShard(url, reason: "header is \(length) bytes")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: headerBytes) as? [String: Any]
        else {
            throw QuantizationError.unreadableShard(url, reason: "header is not a JSON object")
        }
        entries = json
            .compactMap { name, value -> Entry? in
                guard name != "__metadata__",
                    let fields = value as? [String: Any],
                    let shape = fields["shape"] as? [Int],
                    let offsets = fields["data_offsets"] as? [Int],
                    let start = offsets.first
                else { return nil }
                return Entry(name: name, shape: shape, dataOffset: start)
            }
            .sorted { $0.dataOffset < $1.dataOffset }
    }
}
