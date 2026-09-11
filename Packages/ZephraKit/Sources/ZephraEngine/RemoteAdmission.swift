/// Whether a request from a paired device would be queued right now, and if not, why.
///
/// Four answers rather than a Bool, because the device on the other end has to say something,
/// and the three ways a request can fail want three different words on a phone: wait, the Mac
/// is busy with something of its own, or fix the request. The distinction is also the one a
/// host adapter needs to decide whether to retry: `busy` and `refused` are worth asking again
/// in a moment, `badRequest` never is.
public enum RemoteAdmission: Hashable, Sendable {
    /// The request would be queued.
    case admitted
    /// The store is not taking new work at all: a folder is being changed, model storage is
    /// being deleted, or the app is quitting. `GenerationStore.acceptsWork` is the gate.
    case busy(String)
    /// The store takes work, but the engine is not in a state that accepts a generation — no
    /// model is loaded yet, one is being fetched, built or loaded, or the last run failed.
    case refused(String)
    /// Nothing about the request could run: no prompt, a count outside 1...`batchLimit`, or a
    /// model this build's catalog does not know.
    case badRequest(String)

    /// Whether the request would be queued.
    public var isAdmitted: Bool {
        if case .admitted = self { return true }
        return false
    }

    /// The sentence to show the person holding the device, or nil when the request was
    /// admitted and there is nothing to say.
    public var reason: String? {
        switch self {
        case .admitted: nil
        case .busy(let reason), .refused(let reason), .badRequest(let reason): reason
        }
    }
}
