import ZephraCore

/// What the toolbar's model pull-down lists, worked out once and tested without a window.
///
/// The menu is what is on this Mac, not the whole catalog: everything else lives behind More
/// Models…, where a card can say what it downloads and how it would run. Three things are on
/// the list — a model whose files are here, the chosen model whatever its state, and a model
/// whose transfer has something to say, because a transfer somebody started must not disappear
/// from the one menu in the window that names models. A paused transfer and a failed one are
/// what that rule is for above all: those are the two a person has to come back to. A finished
/// one says nothing and needs no rule, since the model is on the disk by then.
enum ModelMenuRows {
    /// One row, as the menu draws it.
    struct Row: Identifiable, Hashable {
        /// The model's `ModelDescriptor.id`, which is also the dot's colour.
        let id: ModelDescriptor.ID
        /// The model, so the menu's action has something to hand the store.
        let model: ModelDescriptor
        /// The secondary fragment after the name, or nil when the name says everything.
        let note: String?
        /// Whether this is the model a press of Generate would run.
        let isChosen: Bool
        /// Whether the row may be pressed. Only memory closes a row: a model that is merely
        /// not downloaded is chosen and fetched from here as it always was.
        let isEnabled: Bool
        /// The tooltip, which is where a greyed row says what it would take.
        let help: String
    }

    /// The rows, in the order the menu draws them: the models this Mac runs first, catalog
    /// order inside each group, which is `ModelCatalog.ordered(for:)`'s own answer.
    /// `transfers` is `ModelDownloads.status(for:)` per model: the sentence the Settings row
    /// and this menu now share — "Downloading 42%", "Download paused", "Download failed" — and
    /// nil for a model with no transfer worth mentioning. It is both the note and the reason a
    /// model is listed, so the two can never disagree about which transfers are live.
    static func rows(
        budget: MemoryBudget,
        availability: [ModelDescriptor.ID: ModelAvailability],
        transfers: [ModelDescriptor.ID: String],
        chosen: ModelDescriptor,
        loaded: ModelDescriptor?,
        residency: WeightResidency?
    ) -> [Row] {
        ModelCatalog.ordered(for: budget)
            .filter { model in
                model.id == chosen.id || transfers[model.id] != nil
                    || availability[model.id] == .available
            }
            .map { model in
                let fit = ModelCatalog.fit(model, budget: budget)
                return Row(
                    id: model.id,
                    model: model,
                    note: note(
                        model, availability: availability[model.id], fit: fit,
                        transfer: transfers[model.id],
                        isLoaded: loaded?.id == model.id, residency: residency),
                    isChosen: model.id == chosen.id,
                    isEnabled: fit.isSelectable,
                    help: fit == .fits
                        ? (availability[model.id]?.reason ?? model.fullName)
                        : fit.reason(for: model, budget: budget))
            }
    }

    /// The fragment after the name. What is happening to the model comes before what it is:
    /// a transfer and the weights being in are both news, and how a model would run here is the
    /// card's job now rather than the menu's. Only a model this Mac cannot hold keeps its memory
    /// note, since that is what the greying means.
    private static func note(
        _ model: ModelDescriptor,
        availability: ModelAvailability?,
        fit: MemoryFit,
        transfer: String?,
        isLoaded: Bool,
        residency: WeightResidency?
    ) -> String? {
        if let transfer { return transfer }
        if isLoaded { return residency == .streamed ? "Streaming" : "Loaded" }
        if !fit.isSelectable { return fit.label }
        if availability?.isObtainable == false { return availability?.label }
        if availability?.needsNetwork == true { return availability?.label }
        if availability == .needsBuild { return availability?.label }
        return nil
    }
}
