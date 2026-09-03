import Foundation

/// A command line that would build something other than what its output directory says.
enum QuantizeUsageError: Error, LocalizedError {
    /// The output directory's name ends in a precision, and it is not the one asked for.
    case precisionDisagreesWithName(bits: Int, directory: String)

    var errorDescription: String? {
        switch self {
        case .precisionDisagreesWithName(let bits, let directory):
            "\(directory) is named for another precision; pass --out to build \(bits) bits somewhere else"
        }
    }

    /// The precision a directory's name claims, from a trailing `-Nbit`, or nil when it claims
    /// none.
    static func bitsNamed(by directory: URL) -> Int? {
        let name = directory.lastPathComponent
        guard name.hasSuffix("bit"), let dash = name.lastIndex(of: "-") else { return nil }
        return Int(name[name.index(after: dash)..<name.index(name.endIndex, offsetBy: -3)])
    }
}
