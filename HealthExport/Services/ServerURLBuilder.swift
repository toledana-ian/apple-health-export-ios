import Foundation

/// Pure URL parsing and endpoint construction for destination servers.
enum ServerURLBuilder {
    struct NormalizedDestination: Equatable, Hashable {
        var scheme: String
        var host: String
        var port: Int?
        var uploadPath: String
    }

    struct ParsedHostInput: Equatable {
        var scheme: String?
        var host: String
        var port: Int?
        var embeddedPath: String?
    }

    // MARK: - Parsing

    static func parseHostInput(_ input: String) -> ParsedHostInput? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            let path = url.path
            let embeddedPath = (path.isEmpty || path == "/") ? nil : path
            return ParsedHostInput(
                scheme: url.scheme?.lowercased(),
                host: host.lowercased(),
                port: url.port,
                embeddedPath: embeddedPath
            )
        }

        if let url = URL(string: "https://\(trimmed)"), let host = url.host, !host.isEmpty {
            let path = url.path
            let embeddedPath = (path.isEmpty || path == "/") ? nil : path
            return ParsedHostInput(
                scheme: url.scheme?.lowercased(),
                host: host.lowercased(),
                port: url.port,
                embeddedPath: embeddedPath
            )
        }

        return nil
    }

    static func normalizeUploadPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return defaultUploadPath }
        let normalized = trimmed.hasPrefix("/") ? trimmed : "/\(trimmed)"
        guard normalized.hasPrefix("/"), !normalized.contains(" ") else { return nil }
        return normalized
    }

    static let defaultUploadPath = DestinationServer.defaultUploadPath

    // MARK: - Normalization

    static func normalizedDestination(
        for server: DestinationServer
    ) -> Result<NormalizedDestination, ServerValidationError> {
        guard let parsed = parseHostInput(server.host) else {
            return .failure(.invalidHost)
        }

        if let port = server.port, !(1 ... 65_535).contains(port) {
            return .failure(.invalidPort)
        }

        let scheme: String
        if let parsedScheme = parsed.scheme {
            scheme = parsedScheme
        } else {
            scheme = server.usesInsecureHTTP ? "http" : "https"
        }

        if scheme != "http" && scheme != "https" {
            return .failure(.invalidHost)
        }

        let resolvedPort = server.port ?? parsed.port

        let uploadPath: String
        if let embedded = parsed.embeddedPath, server.uploadPath == defaultUploadPath {
            uploadPath = embedded
        } else {
            guard let normalizedPath = normalizeUploadPath(server.uploadPath) else {
                return .failure(.invalidUploadPath)
            }
            uploadPath = normalizedPath
        }

        return .success(
            NormalizedDestination(
                scheme: scheme,
                host: parsed.host,
                port: resolvedPort,
                uploadPath: uploadPath
            )
        )
    }

    static func destinationKey(for server: DestinationServer) -> String? {
        switch normalizedDestination(for: server) {
        case .success(let normalized):
            return destinationKey(for: normalized)
        case .failure:
            return nil
        }
    }

    static func destinationKey(for normalized: NormalizedDestination) -> String {
        let portComponent = normalized.port.map { ":\($0)" } ?? ""
        return "\(normalized.scheme)://\(normalized.host)\(portComponent)\(normalized.uploadPath)"
            .lowercased()
    }

    // MARK: - URL building

    static func uploadURL(for server: DestinationServer) -> Result<URL, ServerValidationError> {
        switch normalizedDestination(for: server) {
        case .success(let normalized):
            return uploadURL(for: normalized)
        case .failure(let error):
            return .failure(error)
        }
    }

    static func uploadURL(for normalized: NormalizedDestination) -> Result<URL, ServerValidationError> {
        var components = URLComponents()
        components.scheme = normalized.scheme
        components.host = normalized.host
        components.port = normalized.port
        components.path = normalized.uploadPath

        guard let url = components.url else {
            return .failure(.invalidHost)
        }
        return .success(url)
    }

    static func displayURL(for server: DestinationServer) -> String {
        switch uploadURL(for: server) {
        case .success(let url):
            return url.absoluteString
        case .failure:
            return server.host
        }
    }

    // MARK: - Validation

    static func validate(
        server: DestinationServer,
        existingServers: [DestinationServer],
        excludingServerID: UUID? = nil
    ) -> Result<DestinationServer, ServerValidationError> {
        let trimmedName = server.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return .failure(.emptyName) }

        let trimmedHost = server.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return .failure(.emptyHost) }

        if let port = server.port, !(1 ... 65_535).contains(port) {
            return .failure(.invalidPort)
        }

        if server.auth.type == .customHeader {
            let headerName = server.auth.headerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !headerName.isEmpty else { return .failure(.missingCustomHeaderName) }
        }

        guard case .success(let normalized) = normalizedDestination(for: server) else {
            return .failure(.invalidHost)
        }

        guard normalizeUploadPath(server.uploadPath) != nil else {
            return .failure(.invalidUploadPath)
        }

        let key = destinationKey(for: normalized)
        let duplicate = existingServers.contains { existing in
            guard existing.id != excludingServerID else { return false }
            guard let existingKey = destinationKey(for: existing) else { return false }
            return existingKey == key
        }
        if duplicate {
            return .failure(.duplicateDestination)
        }

        var validated = server
        validated.name = trimmedName
        validated.host = trimmedHost
        if server.auth.type == .customHeader {
            validated.auth.headerName = server.auth.headerName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return .success(validated)
    }
}
