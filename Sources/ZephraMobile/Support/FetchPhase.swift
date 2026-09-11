/// Where a fetch off the Mac has got to, for a view that draws one thing while it waits and
/// another when it will not arrive.
///
/// Three states rather than an optional, because "not here yet" and "not coming" are different
/// pictures on screen and an optional cannot tell them apart: a spinner that never stops is a
/// promise the app cannot keep, and a blank square explains nothing.
enum FetchPhase<Value> {
    /// The bytes are on their way.
    case fetching
    /// They are not coming: the Mac is not answering, or it refused.
    case missing
    /// They arrived.
    case ready(Value)

    /// What arrived, where anything did.
    var value: Value? {
        if case .ready(let value) = self { return value }
        return nil
    }
}
