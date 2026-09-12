import Foundation
import Network

/// As much of a network path as the reconnection needs to know: whether anything can be
/// reached, what it would cost, and over which interfaces.
///
/// A value rather than the `NWPath` itself, for two reasons. One is that `NWPath` cannot be
/// made up, so a decision taken over it could only be exercised by changing the phone's
/// network; the other is that "the path changed" is a question about what is different
/// between two of them, and the answer should not depend on a type whose equality is Apple's.
///
/// The interfaces are kept **in the order the system gave them**, since that order is its
/// preference: Wi-Fi handing over to cellular is the same two names in the other order, and
/// that is exactly the change worth redialling for.
struct LinkPathMark: Equatable, Sendable {
    /// Whether the path can carry anything at all.
    var isSatisfied: Bool
    /// Whether it is somebody's data allowance.
    var isExpensive: Bool
    /// Whether the system has been asked to keep traffic on it small.
    var isConstrained: Bool
    /// What it runs over, most preferred first.
    var interfaces: [String]

    /// A path from its four facts. `nonisolated`, like the one below it, because the system
    /// reports a path on a queue of its own and this app target is main-actor by default.
    nonisolated init(
        isSatisfied: Bool, isExpensive: Bool, isConstrained: Bool, interfaces: [String]
    ) {
        self.isSatisfied = isSatisfied
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.interfaces = interfaces
    }
}

extension LinkPathMark {
    /// What one of the system's paths comes down to.
    nonisolated init(_ path: NWPath) {
        self.init(
            isSatisfied: path.status == .satisfied, isExpensive: path.isExpensive,
            isConstrained: path.isConstrained,
            interfaces: path.availableInterfaces.map(\.name))
    }
}
