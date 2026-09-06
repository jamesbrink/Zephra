import Foundation
import ZephraCore

/// What one benchmark invocation was asked to measure.
struct BenchOptions: Sendable {
    /// The generated image's size, in pixels: `--size N` is square, `--size WxH` is not.
    var size = ImageSize(width: 1024, height: 1024)
    /// How many frames a clip should have, on a model that makes one, or nil for the model's
    /// own default. A picture model clamps whatever is asked to one frame.
    var frames: Int?
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
    /// Whether the run makes preview frames, and reports what they cost. Off by default, so a
    /// timing taken today is comparable with one taken before frames existed.
    var preview = false
    /// A backend to run a snapshot with directly, for a model the catalog does not carry yet.
    var backend: BackendID?
    /// The snapshot directory that backend should load.
    var snapshot: URL?
    /// The catalog identifier of the model to load, defaulting to the app's own default.
    var model = ModelCatalog.default.id
    /// A picture to edit, so the editing path is what gets measured.
    var reference: URL?
    /// How far from it the timed runs start, on a model that starts from a noised copy. Only
    /// read when there is a reference, and clamped to the model's own bounds after that.
    var referenceStrength = 0.6
    /// Whether the weights are streamed from disk on every step rather than held, on a model
    /// whose family can. Off by default, so a timing taken today is the model's own.
    var stream = false
    /// How many layers a streamed load reads ahead, or nil for the backend's own default.
    var streamDepth: Int?
    /// The models folder to look in and download into, or nil for the app's default. The
    /// Makefile passes Settings' folder here so a bench run finds what the app has.
    var models: URL?

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
            case "--preview":
                options.preview = true
            case "--stream":
                options.stream = true
            case "--help", "-h":
                print(usage)
                exit(0)
            case "--size", "--steps", "--runs", "--frames", "--prompt", "--out", "--model",
                "--backend", "--snapshot", "--reference", "--strength", "--stream-depth",
                "--models":
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
        case "--size": options.size = imageSize(value, flag)
        case "--steps": options.steps = positive(value, flag)
        case "--frames": options.frames = positive(value, flag)
        case "--runs": options.runs = positive(value, flag)
        case "--prompt": options.prompt = value
        case "--out": options.output = URL(fileURLWithPath: value)
        case "--model": options.model = resolvedModel(value)
        case "--backend": options.backend = BackendID(value)
        case "--snapshot": options.snapshot = URL(fileURLWithPath: value)
        case "--reference": options.reference = readableFile(value, flag)
        case "--strength": options.referenceStrength = fraction(value, flag)
        case "--stream-depth": options.streamDepth = positive(value, flag)
        case "--models": options.models = URL(fileURLWithPath: value, isDirectory: true)
        default: fail("unknown option \(flag)")
        }
    }

    /// `N` for a square, `WxH` for anything else; both edges positive.
    private static func imageSize(_ value: String, _ flag: String) -> ImageSize {
        let edges = value.lowercased().split(separator: "x").map(String.init)
        switch edges.count {
        case 1: let edge = positive(edges[0], flag); return ImageSize(width: edge, height: edge)
        case 2: return ImageSize(width: positive(edges[0], flag), height: positive(edges[1], flag))
        default: fail("\(flag) wants N or WxH, not \(value)")
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

    /// A strength between zero and one. Out of range is a typo worth stopping for: the model
    /// would clamp it into its own bounds and the report would quietly describe another run.
    private static func fraction(_ value: String, _ flag: String) -> Double {
        guard let number = Double(value), (0...1).contains(number) else {
            fail("\(flag) needs a number from 0 to 1, got \(value)")
        }
        return number
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
}
