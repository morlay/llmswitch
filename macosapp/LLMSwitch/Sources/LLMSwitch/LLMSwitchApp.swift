import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@MainActor
@main
struct LLMSwitchApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var state: AppState
    @StateObject private var toast = ToastCenter()

    init() {
        let state = AppState()
        _state = StateObject(wrappedValue: state)
        Task { await state.bootstrap() }
    }

    var body: some Scene {
        MenuBarExtra(
            "LLMSwitch",
            systemImage: state.gatewayRuntime.isRunning ? "bolt.circle.fill" : "bolt.circle"
        ) {
            MenuBarPanel(state: state)
                .environmentObject(toast)
        }
        .menuBarExtraStyle(.window)
    }
}
