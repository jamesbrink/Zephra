import Foundation

// Headless timing harness for the Z-Image backend. It talks to the same protocol the app
// does, so a number measured here is a number the app can hit.
let options = BenchOptions.parse(CommandLine.arguments)

do {
    let report = try await BenchRunner.run(options)
    print(options.json ? report.jsonText() : report.tableText())
} catch is CancellationError {
    FileHandle.standardError.write(Data("ZephraBench: cancelled\n".utf8))
    exit(130)
} catch {
    let reason = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("ZephraBench: \(reason)\n".utf8))
    exit(1)
}
