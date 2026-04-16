import SwiftUI

struct ProviderCardHeaderView: View {
    let provider: ProviderStatusRow
    let isExpanded: Bool
    let isPerformingAction: Bool
    let onToggleExpanded: () -> Void
    let onEdit: () -> Void
    let onToggleEnabled: () -> Void
    let onDelete: () -> Void

    var body: some View {
        LLMSwitchToolbar(spacing: 10) {
            Button(action: onToggleExpanded) {
                LLMSwitchToolbar(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    LLMSwitchStatusDot(state: provider.healthState)
                    VStack(alignment: .leading, spacing: 2) {
                        LLMSwitchToolbar(spacing: 6) {
                            Text(provider.providerName)
                                .font(.headline)
                            if provider.displayName != provider.providerName {
                                Text(provider.displayName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(provider.baseURL)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Text("\(provider.modelCount)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .help("Cached model count")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .llmSwitchPointingHandCursor()

            EditProviderIconButton(action: onEdit)
            ToggleProviderEnabledIconButton(
                isEnabled: provider.isEnabled,
                isDisabled: isPerformingAction,
                action: onToggleEnabled
            )
            DeleteProviderIconButton(action: onDelete)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .center)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct ProviderCardView: View {
    let provider: ProviderStatusRow
    let isPerformingAction: Bool
    let onToggleModel: (ProviderModelRow, Bool) -> Void

    var body: some View {
        LLMSwitchCard {
            if provider.models.isEmpty {
                Text("No models cached yet. Refresh models first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(provider.models) { modelRow in
                        LLMSwitchListItem(verticalPadding: 2) {
                            Text(modelRow.modelName)
                                .font(.subheadline.weight(.medium))
                            Text(modelRow.featureSummary)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer()
                            Toggle(
                                "",
                                isOn: Binding(
                                    get: { modelRow.isEnabled },
                                    set: { newValue in
                                        onToggleModel(modelRow, newValue)
                                    }
                                )
                            )
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)
                            .disabled(!provider.isEnabled || isPerformingAction)
                        }
                    }
                }
            }

            LLMSwitchListItem(spacing: 12) {
                Text("Last fetched \(provider.lastFetchedAt)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if !provider.isEnabled {
                    Text("Disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                if let errorMessage = provider.errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }
}
