/// A duration as a plain number of seconds, for arithmetic, records, and reports.
extension Duration {
    /// Whole seconds plus the fractional part, to attosecond precision.
    public var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
