import AppKit
import Foundation

/// The question an export asks when some of its files would land on files already in the
/// folder: replace them, keep both under numbered names, or stop.
///
/// Keep Both is the default, as it is in the Finder's own dialog: a stray collision should
/// not block a batch, and the non-destructive answer is the one Return should give. Replace is
/// a plain button rather than a destructive one, matching the Finder.
enum ExportCollisionPrompt {
    enum Choice {
        case keepBoth
        case replace
        case cancel
    }

    /// Asks about `plan`'s collisions in `folder` and returns what was chosen.
    static func ask(about plan: ExportPlan, in folder: URL) -> Choice {
        let alert = NSAlert()
        alert.messageText = headline(for: plan, in: folder)
        alert.informativeText = explanation(for: plan)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }

    /// "3 of 12 images already exist in “Exports”."
    nonisolated static func headline(for plan: ExportPlan, in folder: URL) -> String {
        let colliding = plan.collisions.count
        let total = plan.copies.count + colliding + plan.alreadyThere.count
        let images = total == 1 ? "image" : "images"
        let verb = colliding == 1 ? "exists" : "exist"
        return "\(colliding) of \(total) \(images) already \(verb) in “\(folder.lastPathComponent)”."
    }

    /// The choices, and a note about the files that need no choice because they are already
    /// the very files in this folder.
    nonisolated static func explanation(for plan: ExportPlan) -> String {
        var text = "Replace the existing files, keep both with numbered names, or cancel."
        let there = plan.alreadyThere.count
        if there > 0 {
            let clause = there == 1 ? "1 is already in this folder and is" : "\(there) are already in this folder and are"
            text += " \(clause) left alone."
        }
        return text
    }
}
