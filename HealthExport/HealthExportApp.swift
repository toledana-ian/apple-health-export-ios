import SwiftUI

@main
struct HealthExportApp: App {
    @StateObject private var healthKitManager = HealthKitManager()
    @StateObject private var httpServer = HTTPServer()
    @StateObject private var serverStore = ServerStore()

    var body: some Scene {
        WindowGroup {
            ContentView(
                healthKitManager: healthKitManager,
                httpServer: httpServer,
                serverStore: serverStore
            )
            .onAppear {
                httpServer.healthKitManager = healthKitManager
            }
        }
    }
}
