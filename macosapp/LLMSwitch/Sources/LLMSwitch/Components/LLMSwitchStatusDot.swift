import SwiftUI

struct LLMSwitchStatusDot: View {
    let isHealthy: Bool

    var body: some View {
        Circle()
            .fill(isHealthy ? Color.green : Color.gray.opacity(0.75))
            .frame(width: 8, height: 8)
            .frame(width: 16, height: 16)
            .accessibilityLabel(isHealthy ? "Healthy" : "Unavailable")
    }
}
