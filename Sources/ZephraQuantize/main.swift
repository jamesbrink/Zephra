import Foundation
import ZephraCore
import ZephraQuantization

// Builds a quantized snapshot on this Mac, because no repository publishes one in the manifest
// format the loaders read. All the work is in ZephraQuantization and the family's own plan;
// this only reads the command line and reports what happened.
let options = QuantizeOptions.parse(CommandLine.arguments)

do {
    let family = options.family!
    let plan = family.plan(
        transformer: try QuantizationPrecision(
            bits: options.bits, groupSize: options.groupSize),
        textEncoder: try QuantizationPrecision(
            bits: options.textEncoderBits ?? options.bits,
            groupSize: options.textEncoderGroupSize ?? options.groupSize
        )
    )
    let destination =
        options.output
        ?? ModelCatalog.localModelsDirectory.appending(path: family.defaultOutputName)
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
        try SnapshotQuantizer.quantize(
            source: options.source!,
            destination: destination,
            plan: plan,
            sourceName: options.sourceName ?? family.defaultSourceName
        ) { line in
            FileHandle.standardError.write(Data("\(line)\n".utf8))
        }
    }
    let seconds = Double(elapsed.components.seconds)
    print(String(format: "quantized in %.0f s: %@", seconds, destination.path))
} catch {
    let reason = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("ZephraQuantize: \(reason)\n".utf8))
    exit(1)
}
