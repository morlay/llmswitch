import Foundation
import LLMGateway

@MainActor
final class GatewayRuntime: ObservableObject {
    @Published var isRunning = false
    @Published var listenAddress = ""

    private var service: GatewayService?
    private var server: GatewayHTTPServer?
    private(set) var usageStore: GatewayUsageStore?
    private let logger = GatewayLogger(verbose: false)

    func apply(config: GatewayConfig, state: GatewayRuntimeState) async {
        stop()

        let storeURL = configRootURL(from: config).appendingPathComponent("logs.sqlite")
        let store = GatewayUsageStore(url: storeURL)
        try? await store.open()

        let service = GatewayService(
            config: config, state: state,
            logger: logger, usageStore: store
        )

        let server = GatewayHTTPServer(listenAddress: config.listen) {
            [weak service] request, writer in
            await service?.handleOutput(request, writer: writer)
        }

        self.service = service
        self.server = server
        self.usageStore = store
        self.listenAddress = config.listen.stringValue
    }

    func start() throws {
        try server?.start()
        isRunning = true
    }

    func stop() {
        server?.stop()
        isRunning = false
    }

    func updateService(config: GatewayConfig, state: GatewayRuntimeState) async {
        let storeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/llmswitch/cache/logs.sqlite", isDirectory: false)
        let store = GatewayUsageStore(url: storeURL)
        try? await store.open()

        let newService = GatewayService(
            config: config, state: state, logger: logger, usageStore: store)
        let wasRunning = isRunning

        if wasRunning {
            server?.stop()
            let newServer = GatewayHTTPServer(listenAddress: config.listen) {
                [weak newService] request, writer in
                await newService?.handleOutput(request, writer: writer)
            }
            self.service = newService
            self.server = newServer
            self.usageStore = store
            self.listenAddress = config.listen.stringValue
            try? newServer.start()
        } else {
            let newServer = GatewayHTTPServer(listenAddress: config.listen) {
                [weak newService] request, writer in
                await newService?.handleOutput(request, writer: writer)
            }
            self.service = newService
            self.server = newServer
            self.usageStore = store
            self.listenAddress = config.listen.stringValue
        }
    }

    private func configRootURL(from config: GatewayConfig) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/llmswitch/cache", isDirectory: true)
    }
}
