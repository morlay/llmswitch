import Foundation

public enum SampleConfig {
    public static func defaultConfig(serviceAPIKey: String) -> AppConfig {
        AppConfig(
            app: AppSettings(
                listenAddress: ListenAddress(host: "127.0.0.1", port: 8787),
                modelRefreshIntervalSeconds: 300,
                requestTimeoutSeconds: 600,
                apiKey: serviceAPIKey
            ),
            providers: [:]
        )
    }
}
