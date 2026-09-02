import Foundation
import ZephraBackendZImage

// Headless timing harness for the Z-Image backend. It talks to the same protocol the app
// does, so a number measured here is a number the app can hit.
let options = BenchOptions.parse(CommandLine.arguments)

if options.micro {
    // Token count for a square image: the VAE compresses 8x and the transformer patches 2x2,
    // so a 1024 px side is 64 patches (4,096 tokens), plus a caption stream padded to 64.
    let side = options.size / 8 / 2
    let patches = side * side
    ZImageMicrobench.run(tokens: patches + 64)
    exit(0)
}

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
