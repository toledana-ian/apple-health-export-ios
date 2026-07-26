import SwiftUI

struct ServerFormView: View {
    @ObservedObject var serverStore: ServerStore
    let editingServer: DestinationServer?

    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var host = ""
    @State private var portText = ""
    @State private var uploadPath = DestinationServer.defaultUploadPath
    @State private var usesInsecureHTTP = false
    @State private var isEnabled = true
    @State private var authType: AuthType = .none
    @State private var headerName = ""
    @State private var secret = ""
    @State private var clearSecret = false

    @State private var validationError: String?
    @State private var isTesting = false
    @State private var testResult: ConnectionTestResult?

    private var isEditing: Bool { editingServer != nil }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $name)
                TextField("Host or URL", text: $host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port (optional)", text: $portText)
                    .keyboardType(.numberPad)
                TextField("Upload Path", text: $uploadPath)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            Section {
                Toggle("Use HTTP (insecure)", isOn: $usesInsecureHTTP)
                Toggle("Enabled", isOn: $isEnabled)
            } footer: {
                if usesInsecureHTTP {
                    Label(
                        "HTTP sends data unencrypted. Prefer HTTPS when possible.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
            }

            Section("Authentication") {
                Picker("Type", selection: $authType) {
                    ForEach(AuthType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }

                if authType == .customHeader {
                    TextField("Header Name", text: $headerName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if authType != .none {
                    SecureField(secretFieldPlaceholder, text: $secret)
                    if isEditing, serverStore.hasSecret(for: draftServer) {
                        Toggle("Clear saved secret", isOn: $clearSecret)
                    }
                }
            }

            if let endpointPreview = endpointPreview {
                Section("Endpoint Preview") {
                    Text(endpointPreview)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            Section {
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
                .disabled(isTesting || !canTestConnection)

                if let testResult {
                    Text(testResult.message)
                        .font(.caption)
                        .foregroundStyle(testResult.success ? .green : .red)
                }
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle(isEditing ? "Edit Server" : "Add Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
            }
        }
        .onAppear(perform: loadExisting)
    }

    private var draftServer: DestinationServer {
        DestinationServer(
            id: editingServer?.id ?? UUID(),
            name: name,
            host: host,
            port: Int(portText),
            uploadPath: uploadPath,
            usesInsecureHTTP: usesInsecureHTTP,
            isEnabled: isEnabled,
            auth: AuthMetadata(
                type: authType,
                headerName: authType == .customHeader ? headerName : nil
            ),
            createdAt: editingServer?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    private var endpointPreview: String? {
        switch ServerURLBuilder.uploadURL(for: draftServer) {
        case .success(let url):
            return url.absoluteString
        case .failure:
            return nil
        }
    }

    private var secretFieldPlaceholder: String {
        if isEditing, serverStore.hasSecret(for: draftServer), secret.isEmpty {
            return "Saved secret (leave blank to keep)"
        }
        return authType == .bearer ? "Bearer token" : "Secret value"
    }

    private var canTestConnection: Bool {
        if case .success = ServerURLBuilder.uploadURL(for: draftServer) {
            return true
        }
        return false
    }

    private func loadExisting() {
        guard let server = editingServer else { return }
        name = server.name
        host = server.host
        portText = server.port.map(String.init) ?? ""
        uploadPath = server.uploadPath
        usesInsecureHTTP = server.usesInsecureHTTP
        isEnabled = server.isEnabled
        authType = server.auth.type
        headerName = server.auth.headerName ?? ""
    }

    private func resolvedSecretForTest() -> String? {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if isEditing, !clearSecret { return serverStore.secret(for: draftServer) }
        return nil
    }

    private func testConnection() async {
        validationError = nil
        isTesting = true
        defer { isTesting = false }

        switch ServerURLBuilder.validate(
            server: draftServer,
            existingServers: serverStore.servers,
            excludingServerID: editingServer?.id
        ) {
        case .success(let validated):
            let result = await ServerConnectionTester.testConnection(
                server: validated,
                secret: resolvedSecretForTest()
            )
            testResult = result
        case .failure(let error):
            validationError = error.localizedDescription
        }
    }

    private func save() {
        validationError = nil
        let secretToSave = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        let secretParam = secretToSave.isEmpty ? nil : secretToSave

        do {
            if isEditing {
                _ = try serverStore.updateServer(
                    draftServer,
                    secret: secretParam,
                    clearSecret: clearSecret
                )
            } else {
                _ = try serverStore.addServer(draftServer, secret: secretParam)
            }
            dismiss()
        } catch {
            validationError = error.localizedDescription
        }
    }
}
