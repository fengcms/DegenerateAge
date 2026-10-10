import Foundation
import GameCore

public enum ConfigurationLoader {
    public static func loadBundled() throws -> GameConfiguration {
        guard let url = Bundle.module.url(forResource: "prototype", withExtension: "json") else {
            throw ConfigurationError(issues: ["缺少内置配置 prototype.json"])
        }
        return try decode(Data(contentsOf: url))
    }

    public static func decode(_ data: Data) throws -> GameConfiguration {
        let configuration = try JSONDecoder().decode(GameConfiguration.self, from: data)
        try ConfigurationValidator.validate(configuration)
        return configuration
    }
}

public struct ConfigurationError: LocalizedError, Sendable {
    public let issues: [String]
    public init(issues: [String]) { self.issues = issues }
    public var errorDescription: String? { issues.joined(separator: "\n") }
}

public enum ConfigurationValidator {
    public static func validate(_ configuration: GameConfiguration) throws {
        var issues: [String] = []
        func checkIDs(_ ids: [String], kind: String) {
            var seen: Set<String> = []
            for id in ids {
                if id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("\(kind) ID 不能为空") }
                if !seen.insert(id).inserted { issues.append("\(kind) ID 重复：\(id)") }
            }
        }
        checkIDs(configuration.maps.map(\.id), kind: "地图")
        checkIDs(configuration.enemies.map(\.id), kind: "怪物")
        if !configuration.maps.contains(where: { $0.id == configuration.initialMapId }) {
            issues.append("初始地图引用无效：\(configuration.initialMapId)")
        }
        let enemyIDs = Set(configuration.enemies.map(\.id))
        for enemy in configuration.enemies {
            if !(1...10).contains(enemy.level) || enemy.maxHP <= 0 || enemy.attack < 0 || enemy.defense < 0 ||
                !enemy.attackInterval.isFinite || enemy.attackInterval <= 0 ||
                !enemy.attackRange.isFinite || enemy.attackRange <= 0 ||
                !enemy.movementSpeed.isFinite || enemy.movementSpeed <= 0 ||
                !enemy.aggroRadius.isFinite || enemy.aggroRadius <= 0 ||
                !enemy.leashRadius.isFinite || enemy.leashRadius < enemy.aggroRadius ||
                !enemy.respawnSeconds.isFinite || enemy.respawnSeconds <= 0 {
                issues.append("怪物参数无效：\(enemy.id)")
            }
        }
        for map in configuration.maps {
            if !(1...256).contains(map.columns) || !(1...256).contains(map.rows) {
                issues.append("地图尺寸无效：\(map.id)")
            }
            func inBounds(_ cell: GridCell) -> Bool {
                (0..<max(0, map.columns)).contains(cell.column) && (0..<max(0, map.rows)).contains(cell.row)
            }
            if map.blockedCells.contains(where: { !inBounds($0) }) { issues.append("障碍超出地图边界：\(map.id)") }
            if Set(map.blockedCells).count != map.blockedCells.count { issues.append("障碍格重复：\(map.id)") }
            if !inBounds(map.playerSpawn) || map.blockedCells.contains(map.playerSpawn) { issues.append("玩家出生点无效：\(map.id)") }
            checkIDs(map.enemySpawns.map(\.id), kind: "刷新点")
            for spawn in map.enemySpawns {
                if !enemyIDs.contains(spawn.enemyId) || !map.enemyIds.contains(spawn.enemyId) { issues.append("刷新点怪物引用无效：\(spawn.id)") }
                if !inBounds(spawn.cell) || map.blockedCells.contains(spawn.cell) { issues.append("怪物出生点无效：\(spawn.id)") }
            }
            for id in map.enemyIds where !enemyIDs.contains(id) { issues.append("怪物引用无效：\(map.id) → \(id)") }
        }
        if !issues.isEmpty { throw ConfigurationError(issues: issues) }
    }
}
