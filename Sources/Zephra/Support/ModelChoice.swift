import ZephraCore

/// One model as the first-launch chooser presents it: the catalog entry, how it lands on this
/// Mac's memory, and whether it is the one this Mac would be started on.
///
/// Assembled once by the grid so a card holds three stored properties rather than reading the
/// memory budget for itself, and so every card in one pass is judged against the same budget.
struct ModelChoice: Identifiable, Hashable {
    /// The catalog entry.
    let model: ModelDescriptor
    /// Where it lands against this Mac's GPU working set.
    let fit: MemoryFit
    /// Whether this is the model `ModelCatalog.default(fitting:)` picks for this Mac.
    let isRecommended: Bool
    /// The sentence describing how this model would run here, resolved against the same
    /// budget as `fit`. Held rather than computed at the call site so a view that shows it
    /// need not read the budget for itself.
    let reason: String

    var id: ModelDescriptor.ID { model.id }

    /// What the app has written about this model, when it has anything.
    var portrait: ModelPortrait? { ModelPortrait.of(model) }

    /// Every model, ordered as a picker should list them and judged against one budget.
    static func all(for budget: MemoryBudget) -> [ModelChoice] {
        let recommended = ModelCatalog.default(fitting: budget).id
        return ModelCatalog.ordered(for: budget).map { model -> ModelChoice in
            let fit = ModelCatalog.fit(model, budget: budget)
            return ModelChoice(
                model: model,
                fit: fit,
                isRecommended: model.id == recommended,
                reason: fit.reason(for: model, budget: budget)
            )
        }
    }
}
