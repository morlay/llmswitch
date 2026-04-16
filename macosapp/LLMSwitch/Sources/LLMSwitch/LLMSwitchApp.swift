import SwiftUI

@main
struct LLMSwitchApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var toastCenter = LLMSwitchToastCenter()

    var body: some Scene {
        MenuBarExtra("LLMSwitch", systemImage: model.isProxyRunning ? "bolt.circle.fill" : "bolt.circle") {
            MenuBarPanelView(model: model)
                .environmentObject(toastCenter)
        }
        .menuBarExtraStyle(.window)

        Window("Providers", id: "providers") {
            ProvidersManagementView(model: model)
                .environmentObject(toastCenter)
        }
    }
}
