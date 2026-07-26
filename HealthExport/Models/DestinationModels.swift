import Foundation

// MARK: - Auth

enum AuthType: String, Codable, CaseIterable, Identifiable {
    case none
    case bearer
    case customHeader

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .bearer: return "Bearer Token"
        case .customHeader: return "Custom Header"
        }
    }
}

struct AuthMetadata: Codable, Equatable, Hashable {
    var type: AuthType
    /// Header name when `type` is `.customHeader` (e.g. `X-API-Key`).
    var headerName: String?

    static let none = AuthMetadata(type: .none, headerName: nil)
}

// MARK: - Destination server

struct DestinationServer: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var name: String
    /// Host or full base URL (may include scheme, port, or path segments).
    var host: String
    /// Optional port when not embedded in `host`.
    var port: Int?
    /// Upload path; defaults to `/workouts`.
    var uploadPath: String
    /// When true, use HTTP instead of HTTPS.
    var usesInsecureHTTP: Bool
    var isEnabled: Bool
    var auth: AuthMetadata
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int? = nil,
        uploadPath: String = DestinationServer.defaultUploadPath,
        usesInsecureHTTP: Bool = false,
        isEnabled: Bool = true,
        auth: AuthMetadata = .none,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.uploadPath = uploadPath
        self.usesInsecureHTTP = usesInsecureHTTP
        self.isEnabled = isEnabled
        self.auth = auth
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    static let defaultUploadPath = "/workouts"
}

// MARK: - Push history

enum PushStatus: String, Codable, CaseIterable {
    case success
    case failure
    case pending
}

struct PushHistoryEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var serverId: UUID
    var serverName: String
    /// Stable HealthKit workout UUID used as export identity.
    var workoutHealthKitUUID: UUID
    var timestamp: Date
    var status: PushStatus
    var statusCode: Int?
    var message: String?

    init(
        id: UUID = UUID(),
        serverId: UUID,
        serverName: String,
        workoutHealthKitUUID: UUID,
        timestamp: Date = Date(),
        status: PushStatus,
        statusCode: Int? = nil,
        message: String? = nil
    ) {
        self.id = id
        self.serverId = serverId
        self.serverName = serverName
        self.workoutHealthKitUUID = workoutHealthKitUUID
        self.timestamp = timestamp
        self.status = status
        self.statusCode = statusCode
        self.message = message
    }
}

// MARK: - Connection test result

struct ConnectionTestResult: Equatable {
    var success: Bool
    var statusCode: Int?
    var message: String
}

// MARK: - Validation errors

enum ServerValidationError: LocalizedError, Equatable {
    case emptyName
    case emptyHost
    case invalidHost
    case invalidPort
    case invalidUploadPath
    case missingCustomHeaderName
    case duplicateDestination

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Server name is required."
        case .emptyHost:
            return "Host or URL is required."
        case .invalidHost:
            return "Enter a valid host or URL."
        case .invalidPort:
            return "Port must be between 1 and 65535."
        case .invalidUploadPath:
            return "Upload path must start with '/'."
        case .missingCustomHeaderName:
            return "Custom header name is required."
        case .duplicateDestination:
            return "A server with this destination already exists."
        }
    }
}
