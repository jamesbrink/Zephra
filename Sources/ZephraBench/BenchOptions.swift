import Foundation
import ZephraCore

/// What one benchmark invocation was asked to measure.
struct BenchOptions: Sendable {
    /// Both edges of the generated image, in pixels.
    var size = 1024
    /// Denoising steps per timed run.
    var steps = 9
    /// How many timed runs to average over, after the warm-up.
    var runs = 1
    /// The prompt every run generates from.
    var prompt = "a tin robot reading a newspaper on a park bench, morning light"
    /// Where the last run's image is written.
    var output = URL(fileURLWithPath: "out/bench.png")
    /// Whether to print machine-readable JSON instead of a table.
    var json = false
    /// Whether to skip the pipeline entirely and time individual MLX kernels instead.
    var micro = false
    /// A backend to run a snapshot with directly, for a model the catalog does not carry yet.
    var backend: BackendID?
    /// The snapshot directory that backend should load.
    var snapshot: URL?
    /// The catalog identifier of the model to load, defaulting to the app's own default.
    var model = ModelCatalog.default.id
    /// A picture to edit, so the editing path is what gets measured.
    var reference: URL?

    /// Reads options from the command line, exiting with usage text on anything unrecognised.
    /// A benchmark is run by hand, so a typo should stop it rather than quietly measure the
    /// wrong thing.
    static func parse(_ arguments: [String]) -> BenchOptions {
        var options = BenchOptions()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            switch flag {
            case "--json":
                options.json = true
            case "--micro":
                options.micro = true
            case "--help", "-h":
                print(usage)
                exit(0)
            case "--size", "--steps", "--runs", "--prompt", "--out", "--model", "--backend",
                "--snapshot", "--reference":
                guard index < arguments.count else { fail("\(flag) needs a value") }
                let value = arguments[index]
                index += 1
                apply(flag, value, to: &options)
            default:
                fail("unknown option \(flag)")
            }
        }
        return options
    }

    private static func apply(_ flag: String, _ value: String, to options: inout BenchOptions) {
        switch flag {
        case "--size": options.size = positive(value, flag)
        case "--steps": options.steps = positive(value, flag)
        case "--runs": options.runs = positive(value, flag)
        case "--prompt": options.prompt = value
        case "--out": options.output = URL(fileURLWithPath: value)
        case "--model": options.model = resolvedModel(value)
        case "--backend": options.backend = BackendID(value)
        case "--snapshot": options.snapshot = URL(fileURLWithPath: value)
        case "--reference": options.reference = readableFile(value, flag)
        default: fail("unknown option \(flag)")
        }
    }

    /// Checks a model identifier against the catalog, so a typo names the models that do exist
    /// rather than failing later with a missing-snapshot error.
    private static func resolvedModel(_ value: String) -> String {
        guard ModelCatalog.descriptor(id: value) != nil else {
            fail("unknown model \(value); try one of \(ModelCatalog.all.map(\.id).joined(separator: ", "))")
        }
        return value
    }

    /// Checks that a file is there before anything is loaded: a benchmark run by hand should
    /// stop on a typo rather than quietly measure text-to-image and report it as an edit.
    private static func readableFile(_ value: String, _ flag: String) -> URL {
        let url = URL(fileURLWithPath: value)
        guard FileManager.default.isReadableFile(atPath: url.path(percentEncoded: false)) else {
            fail("\(flag) needs a readable file, and \(value) is not one")
        }
        return url
    }

    private static func positive(_ value: String, _ flag: String) -> Int {
        guard let number = Int(value), number > 0 else {
            fail("\(flag) needs a positive whole number, got \(value)")
        }
        return number
    }

    private static func fail(_ reason: String) -> Never {
        FileHandle.standardError.write(Data("ZephraBench: \(reason)\n\(usage)\n".utf8))
        exit(2)
    }

    private static let usage = """
        usage: ZephraBench [--model ID] [--size N] [--steps N] [--runs N] [--prompt TEXT] \
        [--out PATH] [--json] [--micro] [--backend NAME --snapshot DIR] [--reference IMAGE]

        --model names a catalog entry, so variants can be compared at a fixed seed.
        --backend and --snapshot together run a model the catalog does not carry yet, which
        is how a new family is measured before its entry can be written.
        --reference takes any picture macOS can read and measures the editing path on a
        model that has one; the picture's own pixels add tokens, so its size is part of what
        is being measured.
        --micro times the DiT's individual MLX kernels at --size worth of tokens and
        exits, without loading any weights.
        """
}
