import Foundation

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
            case "--help", "-h":
                print(usage)
                exit(0)
            case "--size", "--steps", "--runs", "--prompt", "--out":
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
        default: fail("unknown option \(flag)")
        }
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
        usage: ZephraBench [--size N] [--steps N] [--runs N] [--prompt TEXT] \
        [--out PATH] [--json]
        """
}
