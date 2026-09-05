import Foundation
import ZephraCore
import ZephraQuantization
import ZephraSnapshot

// Builds a quantized snapshot on this Mac, because no repository publishes one in the manifest
// format the loaders read. All the work is in ZephraQuantization and the family's own plan;
// this only reads the command line, refuses what would build the wrong thing, and reports
// what happened.
let options = QuantizeOptions.parse(CommandLine.arguments)

do {
    let family = options.family!
    let destination =
        options.output
        ?? ModelCatalog.localModelsDirectory.appending(path: family.defaultOutputName)
    // A directory named for one precision must not receive another: the app would load it
    // under a catalog entry that describes it wrongly, an hour after the mistake was made.
    if let named = QuantizeUsageError.bitsNamed(by: destination), named != options.bits {
        throw QuantizeUsageError.precisionDisagreesWithName(
            bits: options.bits, directory: destination.lastPathComponent)
    }
    // Likewise a distilled family's directory must not receive the undistilled model.
    if options.noLora, !options.adapters.isEmpty {
        throw QuantizeUsageError.adapterContradiction
    }
    if family.requiresAdapter, options.adapters.isEmpty {
        guard options.noLora else {
            throw QuantizeUsageError.adapterRequired(family: family.rawValue)
        }
        if options.output == nil || destination.lastPathComponent == family.defaultOutputName {
            throw QuantizeUsageError.undistilledUnderCatalogName(
                directory: family.defaultOutputName)
        }
    }

    let plan = try family.plan(
        transformer: try QuantizationPrecision(
            bits: options.bits, groupSize: options.groupSize),
        textEncoder: try QuantizationPrecision(
            bits: options.textEncoderBits ?? options.bits,
            groupSize: options.textEncoderGroupSize ?? options.groupSize
        ),
        adapters: options.adapters
    )
    // A build named for a catalog entry is checked for space the way the app's own is, and is
    // stamped with the entry's provenance so the app accepts it as its own; any other
    // directory is the user's choice, and gets neither.
    let descriptor = ModelCatalog.all.first {
        $0.isBuiltLocally && $0.id == destination.lastPathComponent
    }
    let interrupt = InterruptFlag()
    let clock = ContinuousClock()
    let elapsed = try clock.measure {
        _ = try SnapshotBuild.pack(
            release: options.source!,
            into: destination,
            plan: plan,
            sourceName: options.sourceName ?? family.defaultSourceName,
            freeSpaceBytes: descriptor?.builtBytes ?? 0,
            note: { line in FileHandle.standardError.write(Data("\(line)\n".utf8)) },
            shouldContinue: interrupt.checkContinue,
            finalize: { partial in
                if let descriptor { try PackedProvenance.write(descriptor, into: partial) }
            }
        )
    }
    let seconds = Double(elapsed.components.seconds)
    let provenance = descriptor.map { "as the catalog's \($0.id)" } ?? "not a catalog entry"
    print(String(format: "quantized in %.0f s (%@): %@", seconds, provenance, destination.path))
} catch is CancellationError {
    FileHandle.standardError.write(Data("ZephraQuantize: stopped; the partial build was removed\n".utf8))
    exit(130)
} catch {
    let reason = (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    FileHandle.standardError.write(Data("ZephraQuantize: \(reason)\n".utf8))
    exit(1)
}
