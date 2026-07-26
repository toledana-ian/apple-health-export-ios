import SwiftUI

struct ServerListView: View {
    @ObservedObject var serverStore: ServerStore
    @ObservedObject var healthKitManager: HealthKitManager
    @ObservedObject var httpServer: HTTPServer

    @State private var showingAddServer = false

    var body: some View {
        List {
            PushLatestWorkoutSection(
                serverStore: serverStore,
                healthKitManager: healthKitManager
            )

            if !healthKitManager.isAuthorised {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HealthKit access is required to export workouts.")
                            .font(.subheadline)
                        Button("Authorise HealthKit") {
                            Task { await healthKitManager.requestAuthorisation() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 4)
                }
            }

            if let error = healthKitManager.lastError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section {
                if serverStore.servers.isEmpty {
                    ContentUnavailableView(
                        "No Servers",
                        systemImage: "server.rack",
                        description: Text("Add a destination server to export workouts.")
                    )
                } else {
                    ForEach(serverStore.servers) { server in
                        NavigationLink(value: server.id) {
                            ServerRowView(
                                server: server,
                                latestPush: serverStore.latestHistoryEntry(for: server.id)
                            )
                        }
                    }
                    .onDelete(perform: deleteServers)
                }
            } header: {
                Text("Destination Servers")
            }

            Section {
                NavigationLink {
                    LocalServerView(
                        healthKitManager: healthKitManager,
                        httpServer: httpServer
                    )
                } label: {
                    Label("Local HTTP Export", systemImage: "antenna.radiowaves.left.and.right")
                }
            } header: {
                Text("On-Device Export")
            } footer: {
                Text("Run a local HTTP server to download workouts from another device on your network.")
            }
        }
        .navigationTitle("Health Export")
        .navigationDestination(for: UUID.self) { serverID in
            if let server = serverStore.server(id: serverID) {
                ServerDetailView(
                    server: server,
                    serverStore: serverStore,
                    healthKitManager: healthKitManager
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddServer = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add Server")
            }
        }
        .sheet(isPresented: $showingAddServer) {
            NavigationStack {
                ServerFormView(serverStore: serverStore, editingServer: nil)
            }
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = serverStore.servers[index]
            serverStore.deleteServer(id: server.id)
        }
    }
}

private struct ServerRowView: View {
    let server: DestinationServer
    let latestPush: PushHistoryEntry?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(server.name)
                    .font(.headline)
                Text(ServerURLBuilder.displayURL(for: server))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let latestPush {
                    HStack(spacing: 4) {
                        Image(
                            systemName: latestPush.status == .success
                                ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(latestPush.status == .success ? .green : .red)
                        if let workout = latestPush.workout {
                            Text(workout.displayTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(latestPush.timestamp, format: .dateTime)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if server.usesInsecureHTTP {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .accessibilityLabel("Uses insecure HTTP")
            }
            if !server.isEnabled {
                Text("Disabled")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
