import Foundation

@MainActor
final class ServerStore: ObservableObject {
    static let maxHistoryEntries = 500

    @Published private(set) var servers: [DestinationServer] = []
    @Published private(set) var pushHistory: [PushHistoryEntry] = []

    private let defaults: UserDefaults
    private let serversKey = "destinationServers"
    private let historyKey = "pushHistory"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Servers

    func load() {
        if let data = defaults.data(forKey: serversKey),
            let decoded = try? JSONDecoder().decode([DestinationServer].self, from: data)
        {
            servers = decoded
        } else {
            servers = []
        }

        if let data = defaults.data(forKey: historyKey),
            let decoded = try? JSONDecoder().decode([PushHistoryEntry].self, from: data)
        {
            pushHistory = decoded
        } else {
            pushHistory = []
        }
    }

    private func persistServers() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        defaults.set(data, forKey: serversKey)
    }

    private func persistHistory() {
        guard let data = try? JSONEncoder().encode(pushHistory) else { return }
        defaults.set(data, forKey: historyKey)
    }

    func addServer(
        _ server: DestinationServer,
        secret: String?
    ) throws -> DestinationServer {
        switch ServerURLBuilder.validate(server: server, existingServers: servers) {
        case .success(var validated):
            validated.updatedAt = Date()
            servers.append(validated)
            persistServers()
            try storeSecretIfNeeded(secret, for: validated)
            return validated
        case .failure(let error):
            throw error
        }
    }

    func updateServer(
        _ server: DestinationServer,
        secret: String?,
        clearSecret: Bool
    ) throws -> DestinationServer {
        switch ServerURLBuilder.validate(
            server: server,
            existingServers: servers,
            excludingServerID: server.id
        ) {
        case .success(var validated):
            validated.updatedAt = Date()
            guard let index = servers.firstIndex(where: { $0.id == validated.id }) else {
                throw ServerValidationError.invalidHost
            }
            servers[index] = validated
            persistServers()

            if clearSecret {
                KeychainService.deleteSecrets(for: validated.id)
            } else {
                try storeSecretIfNeeded(secret, for: validated)
            }
            return validated
        case .failure(let error):
            throw error
        }
    }

    func deleteServer(id: UUID) {
        servers.removeAll { $0.id == id }
        KeychainService.deleteSecrets(for: id)
        persistServers()
    }

    func setEnabled(id: UUID, enabled: Bool) {
        guard let index = servers.firstIndex(where: { $0.id == id }) else { return }
        servers[index].isEnabled = enabled
        servers[index].updatedAt = Date()
        persistServers()
    }

    func server(id: UUID) -> DestinationServer? {
        servers.first { $0.id == id }
    }

    func secret(for server: DestinationServer) -> String? {
        guard let kind = KeychainService.secretKind(for: server.auth) else { return nil }
        return KeychainService.loadSecret(serverID: server.id, kind: kind)
    }

    func hasSecret(for server: DestinationServer) -> Bool {
        secret(for: server) != nil
    }

    private func storeSecretIfNeeded(_ secret: String?, for server: DestinationServer) throws {
        guard let kind = KeychainService.secretKind(for: server.auth) else { return }
        let trimmed = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return }
        try KeychainService.saveSecret(trimmed, serverID: server.id, kind: kind)
    }

    // MARK: - Push history

    func appendHistory(_ entry: PushHistoryEntry) {
        pushHistory.insert(entry, at: 0)
        if pushHistory.count > Self.maxHistoryEntries {
            pushHistory = Array(pushHistory.prefix(Self.maxHistoryEntries))
        }
        persistHistory()
    }

    func history(for serverID: UUID) -> [PushHistoryEntry] {
        pushHistory.filter { $0.serverId == serverID }
    }

    func latestHistoryEntry(for serverID: UUID) -> PushHistoryEntry? {
        history(for: serverID).first
    }

    var enabledServers: [DestinationServer] {
        servers.filter(\.isEnabled)
    }

    func clearHistory() {
        pushHistory = []
        persistHistory()
    }
}
