import Foundation
import ZephraCore

// Headless timing harness. It talks to the same protocol the app does, through the same kind
// of backend registry, so a number measured here is a number the app can hit.
let options = BenchOptions.parse(CommandLine.arguments)
// Every ZEPHRA_* switch, read here and nowhere else; the flags below override a field each.
var environment = InferenceEnvironment.read(ProcessInfo.processInfo.environment)
// A benchmark measures the model, unless it was asked to measure the frames too.
environment.previewInterval = options.preview ? PreviewThrottle.defaultInterval : nil
if let depth = options.streamDepth { environment.streamDepth = depth }

if options.micro {
    // Token count for a square image: the VAE compresses 8x and the transformer patches 2x2,
    // so a 1024 px side is 64 patches (4,096 tokens), plus a caption stream padded to 64.
    let side = options.size / 8 / 2
    let patches = side * side
    let family = ModelCatalog.descriptor(id: options.model)?.backend ?? options.backend ?? .zImage
    BenchBackends.microbench(family: family, tokens: patches + 64)
}

do {
    let report = try await BenchRunner.run(
        options, environment: environment, registry: BenchBackends.registry(environment))
    print(options.json ? report.jsonText() : report.tableText())
} catch is CancellationError {
    FileHandle.standardError.write(Data("ZephraBench: cancelled\n".utf8))
    exit(130)
} catch {
    let reason = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("ZephraBench: \(reason)\n".utf8))
    exit(1)
}
