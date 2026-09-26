import SwiftUI

/// The desktop supplies availability and memory notes; the phone only presents them.
///
/// The row whose weights are in memory carries a plain "Loaded" beside its readiness, which is a
/// different fact from the checkmark: the checkmark is the model this phone's next press names,
/// and the word is what the Mac has actually read in.
struct ModelPickerSheet: View {
    @Environment(GenerationDispatch.self) private var dispatch
    @Environment(PromptDraft.self) private var draft
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ModelManagementLinks()
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
                            if let marker = dispatch.loadedMarker(model.id) {
                                Text(marker)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
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
