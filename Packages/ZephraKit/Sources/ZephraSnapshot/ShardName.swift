import Foundation

/// The `model-00001-of-00002.safetensors` naming a sharded checkpoint uses, read back into
/// the full set of files it implies.
///
/// A release without a `*.safetensors.index.json` still says how many shards there are in
/// every shard's name, so one shard on disk is enough to know what the rest are called.
enum ShardName {
    /// Every file name the numbered shards among `files` promise, whether or not it is there.
    static func expected(among files: [String]) -> Set<String> {
        var expected: Set<String> = []
        for file in files {
            guard let parsed = parse(file) else { continue }
            for index in 1...parsed.total {
                expected.insert(
                    "\(parsed.prefix)-\(padded(index))-of-\(padded(parsed.total)).safetensors")
            }
        }
        return expected
    }

    /// The parts of a shard name, or nil for a file not named like one.
    static func parse(_ file: String) -> (prefix: String, index: Int, total: Int)? {
        let pattern = /^(.+)-(\d{5})-of-(\d{5})\.safetensors$/
        guard let match = file.wholeMatch(of: pattern),
              let index = Int(match.2), let total = Int(match.3), total >= 1
        else { return nil }
        return (String(match.1), index, total)
    }

    private static func padded(_ number: Int) -> String {
        String(format: "%05d", number)
    }
}
