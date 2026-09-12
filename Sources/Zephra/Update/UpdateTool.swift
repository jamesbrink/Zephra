import Foundation

/// Runs one command-line tool and hands back what it said.
///
/// `hdiutil`, `codesign`, `spctl` and `ditto` are all macOS's own, all synchronous, and all
/// take long enough that none of them may run on the main actor — so this is `nonisolated` and
/// the installer calls it from a detached task. Both pipes are read, and read *before* the
/// wait: a tool that fills the pipe buffer while nobody is draining it blocks for ever, and
/// `codesign --verify --verbose=2` writes plenty. What comes back is the reason string in the
/// error a person then reads, which is why stderr is kept rather than thrown away.
enum UpdateTool {
    /// What a tool said and how it ended.
    nonisolated struct Result: Sendable {
        var status: Int32
        var output: String
        /// Whether it succeeded.
        var succeeded: Bool { status == 0 }
        /// The last line it printed, which is the part worth putting in a sentence.
        var lastLine: String {
            output.split(whereSeparator: \.isNewline).last.map(String.init) ?? "no reason given"
        }
    }

    /// Runs `executable` with `arguments` and waits for it.
    nonisolated static func run(_ executable: String, _ arguments: [String]) throws -> Result {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Result(status: process.terminationStatus, output: output)
    }
}
