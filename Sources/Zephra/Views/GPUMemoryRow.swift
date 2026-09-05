import AppKit
import SwiftUI
import ZephraCore
import ZephraEngine

/// How much of this Mac's memory the GPU may keep resident, and how to raise it.
///
/// macOS lets the GPU wire roughly three quarters of RAM; `iogpu.wired_limit_mb` raises that,
/// and every memory verdict in the app follows the raised figure. The row says which figure is
/// in force and, when the chosen model would run with the limit raised and does not run now,
/// shows the command. The app never runs it: it wants an administrator's password, and a
/// setting that takes the whole of RAM from macOS is the person's call to make at a prompt.
struct GPUMemoryRow: View {
    @Environment(GenerationStore.self) private var store
    @Environment(\.memoryBudget) private var budget

    var body: some View {
        LabeledContent("GPU may keep resident") {
            Text(budgetText)
                .monospacedDigit()
        }
        if wouldHelp {
            HStack(alignment: .firstTextBaseline) {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                }
            }
            Text(raiseCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "12.1 GB of 16 GB (macOS default)" or "17.2 GB of 16 GB, set by iogpu.wired_limit_mb".
    private var budgetText: String {
        let working = bytes(budget.gpuWorkingSet)
        let total = bytes(budget.physicalMemory)
        return budget.isWiredLimitRaised
            ? "\(working) of \(total), set by \(GPUMemoryBudget.wiredLimitKey)"
            : "\(working) of \(total) (macOS default)"
    }

    /// Whether raising the limit would let the chosen model run at its default size.
    private var wouldHelp: Bool {
        let fit = ModelCatalog.fit(store.descriptor, budget: budget)
        return !fit.runsAtDefaultSize
            && MemoryFit.wouldFitWithWiredLimitRaised(store.descriptor, budget: budget)
    }

    /// The whole of RAM: the highest value that means anything, and what a person who wants
    /// the model to run would set.
    private var command: String {
        MemoryBudget.wiredLimitCommand(megabytes: budget.physicalMemoryMB)
    }

    private var raiseCaption: String {
        "\(store.descriptor.fullName) needs more than the GPU may keep resident now. Run this "
            + "in Terminal to let the GPU use all of RAM, then relaunch Zephra. It needs an "
            + "administrator password, lasts until the next restart, and leaves macOS less to "
            + "work with; add the line to /etc/sysctl.conf to make it permanent."
    }

    private var caption: String {
        "Models are measured against this figure. `sudo sysctl -w "
            + "\(GPUMemoryBudget.wiredLimitKey)=N` raises it; Zephra reads it at launch."
    }

    private func bytes(_ count: UInt64) -> String {
        Int(count).formatted(.byteCount(style: .memory, spellsOutZero: false))
    }
}

#Preview("GPU memory") {
    Form { Section("GPU memory") { GPUMemoryRow() } }
        .formStyle(.grouped)
        .frame(width: 480)
        .environment(GenerationStore.preview(state: .ready))
}
