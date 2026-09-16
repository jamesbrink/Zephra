import ZephraLinkProtocol

/// What the Macs in scope have in memory, which is a question about a destination rather than
/// about one client.
///
/// The picker lists every enabled Mac's models at once and Auto has not chosen a Mac until the
/// press, so "loaded" on a row is "loaded on a Mac this row could run on" — the same scope
/// `modelReadiness` aggregates over, so the two lines on one row can never disagree. The note
/// under Generate is narrower on purpose: it promises what *this* press does, so it asks the
/// destination alone.
extension GenerationDispatch {
    /// The Macs one row of the picker is about: enabled, and the destination's alone once a Mac
    /// has been named.
    private var scope: [HostConnection] {
        hosts.hosts.filter { $0.preference.enabled && (destination == nil || destination == $0.id) }
    }

    /// The secondary word on one row of the model picker, or nil where there is none.
    func loadedMarker(_ id: String) -> String? {
        scope.lazy
            .compactMap { ModelLoadWord.marker(for: id, engine: $0.client.snapshot?.engine) }
            .first
    }

    /// What a press of Generate would have the destination Mac do first, or nil where it would
    /// simply run.
    func loadNote(for id: String) -> String? {
        guard let target, let snapshot = target.client.snapshot else { return nil }
        return ModelLoadNote.text(
            name: snapshot.model(named: id).label, modelID: id, engine: snapshot.engine,
            availability: snapshot.availability[id])
    }

    /// The model in force, named with what the destination Mac has done about it.
    func modelLabel(for id: String) -> String {
        guard let name = models.first(where: { $0.id == id })?.label else { return "Choose Model" }
        return ModelLoadWord.label(name, modelID: id, engine: target?.client.snapshot?.engine)
    }
}
