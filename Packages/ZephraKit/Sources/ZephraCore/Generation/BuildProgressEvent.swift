/// One progress update from packing a downloaded release into the variant this Mac will load.
public struct BuildProgressEvent: Hashable, Sendable {
    /// The component being packed, as the family names it: "transformer", "text encoder".
    public let component: String
    /// How many components have been written completely.
    public let completedComponents: Int
    /// How many components the build covers in total.
    public let totalComponents: Int
    /// Overall completion from 0 to 1, weighted by the bytes each component holds rather than
    /// by tensor count, so the bar does not run to a third in five seconds and then sit there.
    public let fraction: Double

    /// Creates a build update.
    public init(component: String, completedComponents: Int, totalComponents: Int, fraction: Double) {
        self.component = component
        self.completedComponents = completedComponents
        self.totalComponents = totalComponents
        self.fraction = fraction
    }
}
