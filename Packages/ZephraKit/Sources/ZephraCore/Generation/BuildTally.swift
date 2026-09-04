import Foundation

/// The running total a build's progress events are made from, fed by the packer's own log lines.
///
/// The packer says which component it is working on and when the manifest lands; it does not
/// count tensors, and counting them would not help — a component's tensors are wildly different
/// sizes. So progress moves at component boundaries, weighted by the gigabytes each component
/// reads, which is what keeps the bar honest when one component is three times the other.
///
/// A value type in `ZephraCore` on purpose: every family builds this way and only the weights
/// differ, so the arithmetic is written once and covered by `make test` rather than three times
/// over in suites that need Metal.
public struct BuildTally: Hashable, Sendable {
    private let components: [String]
    private let weights: [String: Double]
    private var completed = 0
    private var current: String

    /// Tallies a build over `components`, in the order the packer converts them, with `weights`
    /// giving how much of the source each one reads. A component with no weight counts as one,
    /// so a plan whose parts are the same size needs no weights at all.
    public init(components: [String], weights: [String: Double] = [:]) {
        self.components = components
        self.weights = weights
        current = components.first ?? ""
    }

    /// The event to report before the packer has said anything, so a bar appears at once.
    public var start: BuildProgressEvent { event(fraction: 0) }

    /// One line from the packer, and the event it means, or nil when it means nothing.
    public mutating func note(_ line: String) -> BuildProgressEvent? {
        // The packer prefixes every line about a component with its directory name and a colon.
        if let name = components.first(where: { line.hasPrefix("\($0): ") }) {
            if name != current {
                completed += 1
                current = name
            }
            return event(fraction: fractionBefore(current))
        }
        // The last line the packer writes, once the manifest is down.
        if line.hasPrefix("wrote ") {
            completed = components.count
            return event(fraction: 1)
        }
        return nil
    }

    /// The share of the build finished before `name` starts.
    private func fractionBefore(_ name: String) -> Double {
        let total = components.reduce(0.0) { $0 + (weights[$1] ?? 1) }
        var done = 0.0
        for component in components {
            if component == name { break }
            done += weights[component] ?? 1
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
