import SwiftUI

struct ContentView: View {
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var httpServer: HTTPServer
    @ObservedObject var serverStore: ServerStore

    var body: some View {
        NavigationStack {
            ServerListView(
                serverStore: serverStore,
                healthKitManager: healthKitManager,
                httpServer: httpServer
            )
        }
    }
}

#Preview {
    ContentView(
        healthKitManager: HealthKitManager(),
        httpServer: HTTPServer(),
        serverStore: ServerStore()
    )
}
