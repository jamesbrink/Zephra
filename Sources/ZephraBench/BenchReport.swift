import Foundation

/// The measurements from one benchmark invocation, in the order a reader wants them.
struct BenchReport: Codable, Sendable {
    /// The Metal device the run used.
    let device: String
    /// The model that was loaded, by descriptor identifier.
    let model: String
    /// Edge length of the generated image, in pixels.
    let size: Int
    /// Denoising steps per timed run.
    let steps: Int
    /// Seconds spent reading weights into memory, excluding any download.
    let loadSeconds: Double
    /// Wall-clock seconds for each timed run, warm-up excluded.
    let runSeconds: [Double]
    /// Mean seconds per denoising step, measured between progress callbacks.
    let meanSecondsPerStep: Double
    /// GPU memory still live after the last run, in megabytes. This is what the app will hold
    /// steadily while a model stays loaded.
    let activeMemoryMB: Double
    /// Highest GPU memory use seen during the whole session, in megabytes. The gap between
    /// this and `activeMemoryMB` is the transient cost of reading the weights.
    let peakMemoryMB: Double
    /// Where the last run's image was written.
    let outputPath: String

    /// Mean wall-clock seconds across the timed runs.
    var meanRunSeconds: Double {
        guard !runSeconds.isEmpty else { return 0 }
        return runSeconds.reduce(0, +) / Double(runSeconds.count)
    }

    /// The report as JSON, with stable key order so runs can be diffed.
    func jsonText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    /// The report as an aligned table for a person reading a terminal.
    func tableText() -> String {
        var lines = [
            row("device", device),
            row("model", model),
            row("image", "\(size) x \(size), \(steps) steps"),
            row("load", seconds(loadSeconds)),
        ]
        for (index, value) in runSeconds.enumerated() {
            lines.append(row("run \(index + 1)", seconds(value)))
        }
        lines.append(row("mean run", seconds(meanRunSeconds)))
        lines.append(row("mean step", seconds(meanSecondsPerStep)))
        lines.append(row("live memory", String(format: "%.0f MB", activeMemoryMB)))
        lines.append(row("peak memory", String(format: "%.0f MB", peakMemoryMB)))
        lines.append(row("image written", outputPath))
        return lines.joined(separator: "\n")
    }

    private func row(_ label: String, _ value: String) -> String {
        label.padding(toLength: 14, withPad: " ", startingAt: 0) + value
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2f s", value)
    }
}
