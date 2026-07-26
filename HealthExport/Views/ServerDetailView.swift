import SwiftUI

struct ServerDetailView: View {
    let server: DestinationServer
    @ObservedObject var serverStore: ServerStore

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

            let history = serverStore.history(for: currentServer.id)
            if !history.isEmpty {
                Section("Recent Push History") {
                    ForEach(history.prefix(20)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(entry.status.rawValue.capitalized)
                                    .font(.caption)
                                    .foregroundStyle(entry.status == .success ? .green : .secondary)
                                Spacer()
                                Text(entry.timestamp, format: .dateTime)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Text(entry.workoutHealthKitUUID.uuidString)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let message = entry.message, !message.isEmpty {
                                Text(message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            Section {
                Button("Edit Server") { showingEdit = true }
                Button("Delete Server", role: .destructive) { showingDeleteConfirm = true }
            }
        }
        .navigationTitle(currentServer.name)
        .navigationBarTitleDisplayMode(.inline)
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
