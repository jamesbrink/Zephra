import Foundation
import ZephraCore
import ZephraQuantization

/// Turns the packer's log lines into build progress, weighted by how much each component holds.
///
/// The packer says which component it is on and when a shard lands; it does not count tensors.
/// So progress moves at component boundaries, weighted by the bytes each component is known to
/// hold, which keeps the bar honest: the transformer and the text encoder are about the same
/// size, and each is half the bar.
///
/// Not Sendable, and it need not be: the packer calls `note` from the thread it runs on, which
/// is the inference executor, and only the event it hands out crosses to the main actor.
final class Flux2BuildProgress {
    private let components: [String]
    private let report: @Sendable (BuildProgressEvent) -> Void
    private var completed = 0
    private var current: String

    /// Gigabytes of the release each component reads while packing, for weighting: the whole
    /// 7.75 GB transformer, and the first 27 of the encoder's 36 layers plus its embedding
    /// table, 6.8 GB of its 8.04. The autoencoder is copied verbatim in a second and left out.
    private static let weights: [String: Double] = ["transformer": 7.75, "text_encoder": 6.8]

    init(plan: QuantizationPlan, report: @escaping @Sendable (BuildProgressEvent) -> Void) {
        components = plan.components.map(\.directoryName)
        current = components.first ?? ""
        self.report = report
        report(event(fraction: 0))
    }

    /// One line from the packer.
    func note(_ line: String) {
        // The packer prefixes every line about a component with its directory name and a colon.
        if let name = components.first(where: { line.hasPrefix("\($0): ") }) {
            if name != current {
                completed += 1
                current = name
            }
            report(event(fraction: fractionBefore(current)))
        } else if line.hasPrefix("wrote ") {
            completed = components.count
            report(event(fraction: 1))
        }
    }

    private func fractionBefore(_ name: String) -> Double {
        let total = components.reduce(0.0) { $0 + (Self.weights[$1] ?? 1) }
        var done = 0.0
        for component in components {
            if component == name { break }
            done += Self.weights[component] ?? 1
        }
        return total > 0 ? done / total : 0
    }

    private func event(fraction: Double) -> BuildProgressEvent {
        BuildProgressEvent(
            component: current.replacingOccurrences(of: "_", with: " "),
            completedComponents: completed,
            totalComponents: components.count,
            fraction: fraction)
    }
}
