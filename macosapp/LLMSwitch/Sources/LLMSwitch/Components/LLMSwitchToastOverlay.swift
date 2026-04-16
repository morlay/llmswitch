import SwiftUI

struct LLMSwitchToastOverlay: View {
    @EnvironmentObject private var toastCenter: LLMSwitchToastCenter

    var body: some View {
        Group {
            if let message = toastCenter.message {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
                    .onTapGesture {
                        toastCenter.hide()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: toastCenter.message)
    }
}
