import Foundation

/// A command line that would build something other than what its output directory says.
enum QuantizeUsageError: Error, LocalizedError {
    /// The output directory's name ends in a precision, and it is not the one asked for.
    case precisionDisagreesWithName(bits: Int, directory: String)
    /// The family is distilled by an adapter and none was given.
    case adapterRequired(family: String)
    /// `--no-lora` would land the undistilled model where the catalog loads the distilled one.
    case undistilledUnderCatalogName(directory: String)
    /// `--no-lora` and `--lora` were both given.
    case adapterContradiction
    /// `--lora` was given for a family whose plan merges no adapter.
    case adapterNotRead(family: String)

    var errorDescription: String? {
        switch self {
        case .precisionDisagreesWithName(let bits, let directory):
            "\(directory) is named for another precision; pass --out to build \(bits) bits somewhere else"
        case .adapterRequired(let family):
            """
            \(family) is distilled by an adapter, and without --lora the build is the \
            undistilled model: it loads under the distilled name and runs, and every picture \
            is soft and hazy. Pass --lora FILE, or --no-lora with --out DIR to build it on \
            purpose.
            """
        case .undistilledUnderCatalogName(let directory):
            """
            --no-lora builds the undistilled model, and \(directory) is where the catalog \
            loads the distilled one from; pass --out naming another directory.
            """
        case .adapterContradiction:
            "--no-lora and --lora cannot both be given"
        case .adapterNotRead(let family):
            "\(family) merges no adapter; --lora would be silently dropped, so it is refused"
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
