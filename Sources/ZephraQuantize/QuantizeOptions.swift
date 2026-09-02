import Foundation
import ZephraCore

/// What one quantization run was asked to build.
struct QuantizeOptions: Sendable {
    /// The full-precision snapshot to read, as a local directory.
    var source: URL?
    /// Where to write the quantized snapshot.
    var output = ModelCatalog.localModelsDirectory.appending(path: "z-image-turbo-4bit")
    /// Bits per weight in the diffusion transformer.
    var bits = 4
    /// Weights per scale in the diffusion transformer.
    var groupSize = 64
    /// Bits per weight in the text encoder, defaulting to the transformer's.
    var textEncoderBits: Int?
    /// Weights per scale in the text encoder, defaulting to the transformer's.
    var textEncoderGroupSize: Int?
    /// The repository the weights came from, recorded in the manifest.
    var sourceName = "Tongyi-MAI/Z-Image-Turbo"

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
        guard options.source != nil else { fail("--source is required") }
        return options
    }

    private static func apply(_ flag: String, _ value: String, to options: inout QuantizeOptions) {
        switch flag {
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
        usage: ZephraQuantize --source DIR [--out DIR] [--bits N] [--group-size N] \
        [--text-encoder-bits N] [--text-encoder-group-size N] [--source-name ID]

        --source is a full-precision Z-Image snapshot directory, such as the one
        `hf download Tongyi-MAI/Z-Image-Turbo` prints. The text encoder options default
        to the transformer's, which is what a plain uniform build wants.
        """
}
