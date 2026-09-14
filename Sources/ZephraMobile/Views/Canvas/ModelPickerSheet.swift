import SwiftUI

/// The desktop supplies availability and memory notes; the phone only presents them.
struct ModelPickerSheet: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                AdoptHostSettings()
                ForEach(dispatch.models) { model in
                    Button {
                        draft.choose(model)
                        dismiss()
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.label).foregroundStyle(.primary)
                                Text(dispatch.modelReadiness(model.id))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            if model.id == draft.modelID {
                                Image(systemName: "checkmark")
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!dispatch.canChooseModel(model.id))
                }
            }
            .navigationTitle("Model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
