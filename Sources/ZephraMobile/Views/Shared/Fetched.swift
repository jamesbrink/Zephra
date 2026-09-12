/// Something that arrived, and the name it arrived for.
///
/// A view that re-runs its fetch whenever the link comes back needs to answer one question
/// first: is what I am holding the thing I am being asked for? Keeping the name beside the
/// value answers it without a fourth stored property, which these views have no room for.
struct Fetched<Value> {
    /// The file's name in the Mac's library, or whatever else identifies the value.
    let name: String
    /// What arrived.
    let value: Value

    /// Whether this is what a view drawing `name` should be showing.
    func matches(_ name: String) -> Bool { self.name == name }
}
