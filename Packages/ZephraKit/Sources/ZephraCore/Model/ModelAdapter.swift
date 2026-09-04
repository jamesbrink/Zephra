/// One low-rank adapter fetched beside a model's release and merged into it while it is packed.
///
/// It is a separate thing from the release because the hub keeps it separately: a distillation
/// is published on its own, against a base model somebody else released, and the two are only
/// put together on the machine that builds the variant. It is named by one file rather than by
/// a pattern because these repositories also ship whole merged checkpoints of twenty gigabytes
/// each, and taking the repository would cost a hundred gigabytes to get two.
///
/// Nothing in the runtime ever sees an adapter: the packer folds it into the weights, so a
/// loaded model is one set of tensors whatever it was made from.
public struct ModelAdapter: Hashable, Sendable {
    /// The Hugging Face repository the adapter is published in.
    public let repoID: String
    /// The revision to fetch, as a descriptor's own source names one.
    public let revision: String
    /// The one file to fetch out of that repository, exactly as the repository names it.
    public let file: String
    /// How many bytes that file is, so a picker can add it to what choosing the model costs.
    public let bytes: Int64

    /// Names one adapter file in one repository.
    public init(repoID: String, revision: String = "main", file: String, bytes: Int64) {
        self.repoID = repoID
        self.revision = revision
        self.file = file
        self.bytes = bytes
    }
}
