import SwiftUI

struct ServerDetailView: View {
    let server: DestinationServer
    @ObservedObject var serverStore: ServerStore
    var healthKitManager: HealthKitManager

    @Environment(\.dismiss) private var dismiss
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?

    private var currentServer: DestinationServer {
        serverStore.server(id: server.id) ?? server
    }

    var body: some View {
        List {
            Section("Details") {
                LabeledContent("Name", value: currentServer.name)
                LabeledContent("Endpoint") {
                    Text(ServerURLBuilder.displayURL(for: currentServer))
                        .font(.system(.caption, design: .monospaced))
                        .multilineTextAlignment(.trailing)
                }
                LabeledContent("Auth", value: currentServer.auth.type.displayName)
                if currentServer.auth.type == .customHeader,
                    let headerName = currentServer.auth.headerName
                {
                    LabeledContent("Header", value: headerName)
                }
                LabeledContent("Secret Saved") {
                    Text(serverStore.hasSecret(for: currentServer) ? "Yes" : "No")
                }
            }

            if currentServer.usesInsecureHTTP {
                Section {
                    Label(
                        "This server uses HTTP. Traffic is not encrypted.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }

            Section {
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { currentServer.isEnabled },
                        set: { serverStore.setEnabled(id: currentServer.id, enabled: $0) }
                    )
                )

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                        }
                    }
                }
                .disabled(isTesting)

                if let testResult {
                    Text(testResult.message)
                        .font(.caption)
                        .foregroundStyle(testResult.success ? .green : .red)
                }
            }

            Section("Export") {
                NavigationLink {
                    PushWorkoutsView(
                        server: currentServer,
                        serverStore: serverStore,
                        healthKitManager: healthKitManager
                    )
                } label: {
                    Label("Push Selected Workouts", systemImage: "arrow.up.doc")
                }
                .disabled(!healthKitManager.isAuthorised || !currentServer.isEnabled)
            }

            let history = serverStore.history(for: currentServer.id)
            Section {
                if history.isEmpty {
                    Text("No deliveries yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.prefix(5)) { entry in
                        PushHistoryRowView(entry: entry)
                    }
                    NavigationLink {
                        PushHistoryView(server: currentServer, serverStore: serverStore)
                    } label: {
                        Text("View All History (\(history.count))")
                    }
                }
            } header: {
                Text("Push History")
            }

        }
        .navigationTitle(currentServer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button {
                        showingEdit = true
                    } label: {
                        Label("Edit Server", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showingDeleteConfirm = true
                    } label: {
                        Label("Delete Server", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                ServerFormView(serverStore: serverStore, editingServer: currentServer)
            }
        }
        .confirmationDialog(
            "Delete this server?",
            isPresented: $showingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                serverStore.deleteServer(id: currentServer.id)
                dismiss()
            }
        }
    }

    private func testConnection() async {
        isTesting = true
        defer { isTesting = false }
        testResult = await ServerConnectionTester.testConnection(
            server: currentServer,
            secret: serverStore.secret(for: currentServer)
        )
    }
}
