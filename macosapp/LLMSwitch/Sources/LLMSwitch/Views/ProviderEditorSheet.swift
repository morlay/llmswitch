import SwiftUI

struct ProviderEditorSheet: View {
    let title: String
    let initialDraft: ProviderDraft
    let onCancel: () -> Void
    let onSubmit: (ProviderDraft) -> Void

    @State private var draft: ProviderDraft

    init(
        title: String,
        initialDraft: ProviderDraft,
        onCancel: @escaping () -> Void,
        onSubmit: @escaping (ProviderDraft) -> Void
    ) {
        self.title = title
        self.initialDraft = initialDraft
        self.onCancel = onCancel
        self.onSubmit = onSubmit
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title3.weight(.semibold))

            Form {
                TextField("Provider Name", text: $draft.name)
                TextField("Display Name (Optional)", text: $draft.displayName)
                TextField("Base URL", text: $draft.baseURL)
                TextField("API Key", text: $draft.apiKey)
                Toggle("Enabled", isOn: $draft.enabled)
            }
            .formStyle(.grouped)

            LLMSwitchToolbar {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Save") {
                    onSubmit(draft)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .background {
            LLMSwitchOutlineSuppressor()
        }
    }
}
