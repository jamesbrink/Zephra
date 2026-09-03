import Foundation

/// A command line that would build something other than what its output directory says.
enum QuantizeUsageError: Error, LocalizedError {
    /// A precision other than four bits was asked for without saying where to put it.
    case precisionNeedsAnOutput(bits: Int, defaultName: String)

    var errorDescription: String? {
        switch self {
        case .precisionNeedsAnOutput(let bits, let defaultName):
            "the default output directory is \(defaultName), which names four bits; pass --out to build \(bits) bits somewhere else"
        }
    }
}
