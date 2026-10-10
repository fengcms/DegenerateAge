import Foundation
import GameCore
import GameData
import GamePersistence

@main
struct ConfigurationTests {
    func testBundledConfigurationLoads() throws {
        let config = try ConfigurationLoader.loadBundled()
        expect(config.initialMapId == "test_camp")
        expect(config.enemies.first?.id == "corrupted_wolf")
    }

    func testRejectsDuplicateIDs() throws {
        var object = try bundledObject()
        let enemies = try require(object["enemies"] as? [[String: Any]])
        object["enemies"] = enemies + enemies
        do {
            _ = try decode(object)
            fatalError("Expected invalid configuration to fail")
        } catch {
            expect(error.localizedDescription.contains("ID 重复"))
        }
    }

    func testRejectsInvalidReferencesAndSpawn() throws {
        var object = try bundledObject()
        object["initialMapId"] = "missing"
        var maps = try require(object["maps"] as? [[String: Any]])
        maps[0]["enemyIds"] = ["missing_enemy"]
        maps[0]["playerSpawn"] = ["column": 3, "row": 3]
        object["maps"] = maps
        do {
            _ = try decode(object)
            fatalError("Expected invalid configuration to fail")
        } catch {
            let message = error.localizedDescription
            expect(message.contains("初始地图引用无效"))
            expect(message.contains("怪物引用无效"))
            expect(message.contains("玩家出生点无效"))
        }
    }

    func testRejectsInvalidDimensionsAndEnemyStats() throws {
        var object = try bundledObject()
        var maps = try require(object["maps"] as? [[String: Any]])
        maps[0]["columns"] = 0
        object["maps"] = maps
        var enemies = try require(object["enemies"] as? [[String: Any]])
        enemies[0]["level"] = 11
        enemies[0]["maxHP"] = 0
        object["enemies"] = enemies
        do {
            _ = try decode(object)
            fatalError("Expected invalid configuration to fail")
        } catch {
            expect(error.localizedDescription.contains("地图尺寸无效"))
            expect(error.localizedDescription.contains("怪物参数无效"))
        }
    }

    func testMalformedJSONFails() {
        do {
            _ = try ConfigurationLoader.decode(Data("{".utf8))
            fatalError("Malformed JSON unexpectedly loaded")
        } catch {}
    }

    func testSaveSnapshotRoundTrip() throws {
        let save = GameSave(slotId: 1, savedAt: Date(timeIntervalSince1970: 100), player: PlayerState(), mapId: "test_camp", position: GridPosition(column: 6, row: 6))
        let data = try JSONEncoder().encode(save)
        try expect(try JSONDecoder().decode(GameSave.self, from: data) == save)
    }

    static func main() throws {
        let checks = ConfigurationTests()
        try checks.testBundledConfigurationLoads()
        try checks.testRejectsDuplicateIDs()
        try checks.testRejectsInvalidReferencesAndSpawn()
        try checks.testRejectsInvalidDimensionsAndEnemyStats()
        checks.testMalformedJSONFails()
        try checks.testSaveSnapshotRoundTrip()
        print("PASS: 6 configuration / snapshot checks")
        try CombatChecks.run()
    }
    private func expect(_ condition: @autoclosure () throws -> Bool) rethrows {
        if try !condition() { fatalError("Rule check failed") }
    }
    private func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CheckError.missingValue }
        return value
    }
    private enum CheckError: Error { case missingValue }

    private func bundledObject() throws -> [String: Any] {
        let data = try JSONEncoder().encode(ConfigurationLoader.loadBundled())
        return try require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    private func decode(_ object: [String: Any]) throws -> GameConfiguration {
        try ConfigurationLoader.decode(JSONSerialization.data(withJSONObject: object))
    }
}
