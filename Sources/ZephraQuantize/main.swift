import Foundation
import ZephraBackendZImage

// Builds a quantized Z-Image snapshot on this Mac, because no repository publishes one in the
// manifest format the vendored loader reads. All the work is in the backend package; this only
// reads the command line and reports what happened.
let options = QuantizeOptions.parse(CommandLine.arguments)

do {
    let precision = try QuantizationPrecision(bits: options.bits, groupSize: options.groupSize)
    let recipe = QuantizationRecipe(
        transformer: precision,
        textEncoder: try QuantizationPrecision(
            bits: options.textEncoderBits ?? options.bits,
            groupSize: options.textEncoderGroupSize ?? options.groupSize
        )
    )
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
        try ZImageWeightQuantizer.quantize(
            source: options.source!,
            destination: options.output,
            recipe: recipe,
            sourceName: options.sourceName
        ) { line in
            FileHandle.standardError.write(Data("\(line)\n".utf8))
        }
    }
    let seconds = Double(elapsed.components.seconds)
    print(String(format: "quantized in %.0f s: %@", seconds, options.output.path))
} catch {
    let reason = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("ZephraQuantize: \(reason)\n".utf8))
    exit(1)
}
