import ZephraLinkProtocol

extension GenerationDispatch {
    private func options(_ id: String) -> [(ModelSummary, AvailabilityDTO?)] {
        hosts.hosts.compactMap { host in
            guard host.preference.enabled, destination == nil || destination == host.id,
                  let snapshot = host.client.snapshot,
                  let model = snapshot.models.first(where: { $0.id == id }) else { return nil }
            return (model, snapshot.availability[id])
        }
    }
    func canChooseModel(_ id: String) -> Bool {
        options(id).contains { $0.0.isChoosable(availability: $0.1) }
    }
    func modelReadiness(_ id: String) -> String {
        let choices = options(id)
        if !canChooseModel(id) {
            return choices.first.map { $0.0.note(availability: $0.1) ?? "Unavailable on this Mac" }
                ?? "No enabled Mac has this model"
        }
        if destination != nil, let choice = choices.first {
            return choice.0.note(availability: choice.1) ?? "Ready"
        }
        let count = hosts.hosts.filter { host in
            guard host.preference.enabled, host.client.connection.isLive,
                  let snapshot = host.client.snapshot,
                  let model = snapshot.models.first(where: { $0.id == id }) else { return false }
            return model.isSelectable && snapshot.availability[id]?.kind == .available
        }.count
        return "Ready on \(count) \(count == 1 ? "Mac" : "Macs")"
    }
}
