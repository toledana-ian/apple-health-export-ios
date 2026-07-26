import XCTest
@testable import HealthExport

@MainActor
final class ServerStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "ServerStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testAppendHistoryTrimsToMaxEntries() {
        let store = ServerStore(defaults: defaults)
        let serverId = UUID()

        for index in 0 ..< (ServerStore.maxHistoryEntries + 25) {
            store.appendHistory(
                PushHistoryEntry(
                    serverId: serverId,
                    serverName: "Test",
                    workoutHealthKitUUID: UUID(),
                    timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                    status: .success
                )
            )
        }

        XCTAssertEqual(store.pushHistory.count, ServerStore.maxHistoryEntries)
        XCTAssertEqual(
            store.pushHistory.first?.timestamp,
            Date(timeIntervalSince1970: TimeInterval(ServerStore.maxHistoryEntries + 24))
        )
    }

    func testAppendHistoryPersistsBoundedEntries() throws {
        let store = ServerStore(defaults: defaults)
        let serverId = UUID()

        for _ in 0 ..< (ServerStore.maxHistoryEntries + 5) {
            store.appendHistory(
                PushHistoryEntry(
                    serverId: serverId,
                    serverName: "Test",
                    workoutHealthKitUUID: UUID(),
                    status: .success
                )
            )
        }

        let reloaded = ServerStore(defaults: defaults)
        XCTAssertEqual(reloaded.pushHistory.count, ServerStore.maxHistoryEntries)
    }

    func testLegacyPushHistoryEntryDecodesWithoutNewFields() throws {
        let legacy = PushHistoryEntry(
            serverId: UUID(),
            serverName: "Legacy",
            workoutHealthKitUUID: UUID(),
            status: .failure,
            statusCode: 500,
            message: "Failed (HTTP 500)"
        )
        let data = try JSONEncoder().encode([legacy])
        let decoded = try JSONDecoder().decode([PushHistoryEntry].self, from: data)

        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded[0].id, legacy.id)
        XCTAssertNil(decoded[0].workout)
        XCTAssertNil(decoded[0].pushStartedAt)
    }
}
