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
    /// The step the loop actually began at, counting from one.
    ///
    /// 1 for an ordinary run. Starting from a reference picture joins the schedule partway
    /// down, so `steps - firstStep + 1` steps ran and the wall-clock time is against that,
    /// not against `steps`.
    let firstStep: Int
    /// How far from the picture the runs started, when the model reads a strength at all.
    /// Nil for a plain run, and for a model that conditions on the picture directly.
    let referenceStrength: Double?
    /// Seconds spent reading weights into memory, excluding any download.
    let loadSeconds: Double
    /// Wall-clock seconds for each timed run, warm-up excluded.
    let runSeconds: [Double]
    /// Mean seconds per denoising step, measured between progress callbacks.
    let meanSecondsPerStep: Double
    /// How many preview frames the runs made, or nil when frames were off. Far fewer than the
    /// steps: the backends throttle them to one every three quarters of a second.
    let previewFrames: Int?
    /// Mean seconds one preview frame took to decode, or nil when frames were off.
    let meanPreviewSeconds: Double?
    /// Where the last preview frame was written, or nil when there was none to write.
    let previewPath: String?
    /// Whether the weights were held or streamed, as `WeightResidency`'s raw value. What
    /// actually ran: a family that cannot stream reports resident whatever was asked.
    let weightResidency: String
    /// Gigabytes of weights read from disk per step when streaming, or nil when held.
    let streamedGBPerStep: Double?
    /// The rate the last streamed pass read at, in gigabytes per second, or nil when held.
    /// Reads and compute together: a rate near the disk's own says the step is read-bound.
    let streamReadGBps: Double?
    /// GPU memory still live after the last run, in megabytes. This is what the app will hold
    /// steadily while a model stays loaded.
    let activeMemoryMB: Double
    /// GPU memory the allocator is keeping for reuse after the last run, in megabytes. When
    /// streaming, a figure that holds steady across steps says the blocks' buffers are being
    /// recycled rather than freshly allocated.
    let cacheMemoryMB: Double
    /// Highest GPU memory use seen during the whole session, in megabytes. The gap between
    /// this and `activeMemoryMB` is the transient cost of reading the weights.
    let peakMemoryMB: Double
    /// Where the last run's image was written.
    let outputPath: String
    /// The picture the runs edited, when they edited one. A path, not a flag: it is what makes
    /// a recorded run reproducible.
    let referencePath: String?

    /// Mean wall-clock seconds across the timed runs.
    var meanRunSeconds: Double {
        guard !runSeconds.isEmpty else { return 0 }
        return runSeconds.reduce(0, +) / Double(runSeconds.count)
    }

    /// How many denoising steps each timed run actually took.
    var effectiveSteps: Int { max(0, steps - firstStep + 1) }

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
        if let referencePath {
            lines.insert(row("reference", referencePath), at: 3)
        }
        if let referenceStrength {
            lines.insert(
                row(
                    "strength",
                    String(
                        format: "%.2f, from step %d of %d (%d steps ran)",
                        referenceStrength, firstStep, steps, effectiveSteps)),
                at: 4)
        }
        for (index, value) in runSeconds.enumerated() {
            lines.append(row("run \(index + 1)", seconds(value)))
        }
        lines.append(row("mean run", seconds(meanRunSeconds)))
        lines.append(row("mean step", seconds(meanSecondsPerStep)))
        if let previewFrames, let meanPreviewSeconds {
            lines.append(
                row(
                    "preview",
                    String(
                        format: "%d frames, %.0f ms each",
                        previewFrames, meanPreviewSeconds * 1000)))
        }
        if let previewPath {
            lines.append(row("frame written", previewPath))
        }
        lines.append(row("weights", weightResidency))
        if let streamedGBPerStep, let streamReadGBps {
            lines.append(
                row(
                    "streamed",
                    String(format: "%.1f GB per step at %.2f GB/s", streamedGBPerStep, streamReadGBps)))
        }
        lines.append(row("live memory", String(format: "%.0f MB", activeMemoryMB)))
        lines.append(row("cached", String(format: "%.0f MB", cacheMemoryMB)))
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
