import Foundation
import ZephraCore

/// What one quantization run was asked to build.
struct QuantizeOptions: Sendable {
    /// Which family's plan to build with. Required, and deliberately without a default: a wrong
    /// default silently produces the wrong artifact an hour later.
    var family: QuantizeFamily?
    /// The full-precision snapshot to read, as a local directory.
    var source: URL?
    /// Where to write the quantized snapshot, defaulting to the family's own directory.
    var output: URL?
    /// Bits per weight in the diffusion transformer.
    var bits = 4
    /// Weights per scale in the diffusion transformer.
    var groupSize = 64
    /// Bits per weight in the text encoder, defaulting to the transformer's.
    var textEncoderBits: Int?
    /// Weights per scale in the text encoder, defaulting to the transformer's.
    var textEncoderGroupSize: Int?
    /// The repository the weights came from, recorded in the manifest. Defaults to the
    /// family's usual source.
    var sourceName: String?

    /// Reads options from the command line, exiting with usage text on anything unrecognised.
    static func parse(_ arguments: [String]) -> QuantizeOptions {
        var options = QuantizeOptions()
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            index += 1
            if flag == "--help" || flag == "-h" {
                print(usage)
                exit(0)
            }
            guard index < arguments.count else { fail("\(flag) needs a value") }
            let value = arguments[index]
            index += 1
            apply(flag, value, to: &options)
        }
        guard options.family != nil else { fail("--family is required (\(QuantizeFamily.names))") }
        guard options.source != nil else { fail("--source is required") }
        return options
    }

    private static func apply(_ flag: String, _ value: String, to options: inout QuantizeOptions) {
        switch flag {
        case "--family":
            guard let family = QuantizeFamily(rawValue: value) else {
                fail("unknown --family \(value); use \(QuantizeFamily.names)")
            }
            options.family = family
        case "--source": options.source = URL(fileURLWithPath: value)
        case "--out": options.output = URL(fileURLWithPath: value)
        case "--source-name": options.sourceName = value
        case "--bits": options.bits = positive(value, flag)
        case "--group-size": options.groupSize = positive(value, flag)
        case "--text-encoder-bits": options.textEncoderBits = positive(value, flag)
        case "--text-encoder-group-size": options.textEncoderGroupSize = positive(value, flag)
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
        FileHandle.standardError.write(Data("ZephraQuantize: \(reason)\n\(usage)\n".utf8))
        exit(2)
    }

    private static let usage = """
        usage: ZephraQuantize --family NAME --source DIR [--out DIR] [--bits N] \
        [--group-size N] [--text-encoder-bits N] [--text-encoder-group-size N] [--source-name ID]

        --family is one of \(QuantizeFamily.names) and decides which plan is used: which
        directories are packed, which tensors are left alone, and where the result is written.
        --source is a full-precision snapshot directory, such as the one `hf download` prints.
        The text encoder options default to the transformer's, which is what a plain uniform
        build wants.
        """
}
