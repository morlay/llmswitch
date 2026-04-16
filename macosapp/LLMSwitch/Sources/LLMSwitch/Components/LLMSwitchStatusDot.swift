import SwiftUI

struct LLMSwitchStatusDot: View {
    let state: ProviderHealthState

    var body: some View {
        Circle()
            .fill(state == .healthy ? Color.green : Color.gray.opacity(0.75))
            .frame(width: 8, height: 8)
            .frame(width: 16, height: 16)
            .accessibilityLabel(state == .healthy ? "Healthy" : "Unavailable")
    }
}
