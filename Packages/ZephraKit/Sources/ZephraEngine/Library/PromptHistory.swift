import Foundation
import Observation
import ZephraCore

/// Bounded prompt-only journal. A failed image remains a useful previous request.
@MainActor @Observable
public final class PromptHistory {
    public private(set) var entries: [PromptHistoryEntry] = []
    public private(set) var failure: String?
    @ObservationIgnored private let file: URL?
    @ObservationIgnored private var seeded = false
    public init(file: URL? = nil) {
        self.file = file
        if let file, let data = try? Data(contentsOf: file) {
            do { entries = try JSONDecoder().decode([PromptHistoryEntry].self, from: data); seeded = true }
            catch { failure = "Saved prompt history could not be read." }
        }
        bound()
    }
    public func record(_ prompt: String, id: UUID, at date: Date = Date()) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entries.contains(where: { $0.id == id }) else { return }
        entries.insert(PromptHistoryEntry(id: id, prompt: prompt, createdAt: date), at: 0)
        bound(); save()
    }
    /// Seeds only once; one batch is one press even when several seeds made images.
    public func seed(_ items: [LibraryItem]) {
        guard !seeded, !items.isEmpty else { return }
        seeded = true
        var batches = Set<UUID>()
        for item in items.reversed() {
            guard let record = item.provenance.record else { continue }
            let id = record.batchID ?? UUID()
            guard batches.insert(id).inserted else { continue }
            if entries.contains(where: { $0.id == id }) { continue }
            entries.append(PromptHistoryEntry(id: id, prompt: item.prompt, createdAt: record.createdAt))
        }
        entries.sort { $0.createdAt > $1.createdAt }
        bound(); save()
    }
    private func bound() {
        entries = Array(entries.prefix(100))
        var bytes = 0
        entries = entries.filter { entry in
            let cost = entry.prompt.utf8.count
            guard cost <= 262_144 - bytes else { return false }
            bytes += cost; return true
        }
        // JSON escaping can expand control characters sixfold; keep a workflow reply
        // comfortably below the transport's 1 MiB frame even for such a prompt.
        while !entries.isEmpty, (try? JSONEncoder().encode(entries).count) ?? 0 > 524_288 {
            entries.removeLast()
        }
    }
    private func save() {
        guard let file else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(entries).write(to: file, options: .atomic)
            failure = nil
        } catch { failure = "Prompt history could not be saved. " + error.localizedDescription }
    }
}
