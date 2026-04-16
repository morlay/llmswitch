import SwiftUI

private struct ProviderEditorState: Identifiable {
    let id = UUID()
    let originalName: String?
    var draft: ProviderDraft
}

struct ProvidersManagementView: View {
    @ObservedObject var model: AppModel

    @State private var statusMessage = ""
    @State private var isPerformingAction = false
    @State private var editingProvider: ProviderEditorState?
    @State private var providerPendingDeletion: ProviderStatusRow?
    @State private var collapsedProviderNames: Set<String> = []
    @State private var titlebarHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                providersSection

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, titlebarHeight)
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(minWidth: 860, minHeight: 620)
        .overlay(alignment: .bottom) {
            LLMSwitchToastOverlay()
                .padding(.bottom, 8)
        }
        .background {
            LLMSwitchOutlineSuppressor()
        }
        .background {
            LLMSwitchWindowConfigurator { window in
                window.titlebarAppearsTransparent = false
                window.backgroundColor = .windowBackgroundColor
                window.styleMask.insert(.fullSizeContentView)

                let resolvedTitlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
                if abs(titlebarHeight - resolvedTitlebarHeight) > 0.5 {
                    titlebarHeight = resolvedTitlebarHeight
                }
            }
        }
        .sheet(item: $editingProvider) { editor in
            ProviderEditorSheet(
                title: editor.originalName == nil ? "Add Provider" : "Edit Provider",
                initialDraft: editor.draft,
                onCancel: {
                    editingProvider = nil
                },
                onSubmit: { draft in
                    saveProvider(editor: editor, draft: draft)
                }
            )
        }
        .alert(
            "Delete Provider?",
            isPresented: Binding(
                get: { providerPendingDeletion != nil },
                set: { newValue in
                    if !newValue {
                        providerPendingDeletion = nil
                    }
                }
            ),
            presenting: providerPendingDeletion
        ) { provider in
            Button("Delete", role: .destructive) {
                deleteProvider(provider)
            }
            Button("Cancel", role: .cancel) {
                providerPendingDeletion = nil
            }
        } message: { provider in
            Text("This will remove \(provider.providerName) and its model switches.")
        }
    }

    private var providersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LLMSwitchToolbar {
                Text("Providers")
                    .font(.title3.weight(.semibold))
                Spacer()
                AddProviderIconButton {
                    editingProvider = ProviderEditorState(
                        originalName: nil,
                        draft: ProviderDraft(name: "", displayName: "", baseURL: "https://", apiKey: "", enabled: true)
                    )
                }
            }

            if model.providerStatuses.isEmpty {
                Text("No providers yet. Add one to start fetching models.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.providerStatuses) { provider in
                        Section {
                            if isProviderExpanded(provider) {
                                ProviderCardView(
                                    provider: provider,
                                    isPerformingAction: isPerformingAction,
                                    onToggleModel: { modelRow, enabled in
                                        Task {
                                            await model.setProviderModelEnabled(
                                                providerName: modelRow.providerName,
                                                modelName: modelRow.modelName,
                                                enabled: enabled
                                            )
                                        }
                                    }
                                )
                                .padding(.top, 6)
                            }
                        } header: {
                            ProviderCardHeaderView(
                                provider: provider,
                                isExpanded: isProviderExpanded(provider),
                                isPerformingAction: isPerformingAction,
                                onToggleExpanded: {
                                    toggleProviderExpanded(provider)
                                },
                                onEdit: {
                                    if let draft = model.draftForProvider(named: provider.providerName) {
                                        editingProvider = ProviderEditorState(originalName: provider.providerName, draft: draft)
                                    }
                                },
                                onToggleEnabled: {
                                    setProviderEnabled(provider)
                                },
                                onDelete: {
                                    providerPendingDeletion = provider
                                }
                            )
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                }
            }
        }
    }

    private func isProviderExpanded(_ provider: ProviderStatusRow) -> Bool {
        !collapsedProviderNames.contains(provider.providerName)
    }

    private func toggleProviderExpanded(_ provider: ProviderStatusRow) {
        if collapsedProviderNames.contains(provider.providerName) {
            collapsedProviderNames.remove(provider.providerName)
        } else {
            collapsedProviderNames.insert(provider.providerName)
        }
    }

    private func saveProvider(editor: ProviderEditorState, draft: ProviderDraft) {
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            do {
                if let originalName = editor.originalName {
                    try await model.updateProvider(originalName: originalName, draft: draft)
                    statusMessage = "Provider updated"
                } else {
                    try await model.addProvider(draft)
                    statusMessage = "Provider added"
                }
                editingProvider = nil
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    private func deleteProvider(_ provider: ProviderStatusRow) {
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            do {
                try await model.deleteProvider(provider.providerName)
                statusMessage = "Provider deleted"
            } catch {
                statusMessage = error.localizedDescription
            }
            providerPendingDeletion = nil
        }
    }

    private func setProviderEnabled(_ provider: ProviderStatusRow) {
        Task {
            isPerformingAction = true
            defer { isPerformingAction = false }
            do {
                try await model.setProviderEnabled(provider.providerName, enabled: !provider.isEnabled)
                statusMessage = provider.isEnabled ? "Provider disabled" : "Provider enabled"
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }
}
