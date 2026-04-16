import Foundation

@MainActor
final class LLMSwitchToastCenter: ObservableObject {
    @Published private(set) var message: String?

    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, durationNanoseconds: UInt64 = 1_500_000_000) {
        self.message = message

        dismissTask?.cancel()
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: durationNanoseconds)
            guard !Task.isCancelled else {
                return
            }
            self.message = nil
        }
    }

    func hide() {
        dismissTask?.cancel()
        dismissTask = nil
        message = nil
    }
}
