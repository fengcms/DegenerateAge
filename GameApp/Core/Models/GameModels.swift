import Foundation

public struct GridPosition: Codable, Equatable, Sendable {
    public var column: Double
    public var row: Double
    public init(column: Double, row: Double) { self.column = column; self.row = row }
}

public struct PlayerState: Codable, Equatable, Sendable {
    public var name: String
    public var level: Int
    public var xp: Int
    public var currentHP: Int
    public var currentMP: Int
    public init(name: String = "守护者", level: Int = 1, xp: Int = 0, currentHP: Int = 100, currentMP: Int = 50) {
        self.name = name; self.level = level; self.xp = xp
        self.currentHP = currentHP; self.currentMP = currentMP
    }
}

public struct EnemyDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let level: Int
    public let maxHP: Int
    public let attack: Int
    public let defense: Int
    public let attackInterval: Double
    public let attackRange: Double
    public let movementSpeed: Double
    public let aggroRadius: Double
    public let leashRadius: Double
    public let respawnSeconds: Double
}

public struct GridCell: Codable, Equatable, Hashable, Sendable {
    public let column: Int
    public let row: Int
    public init(column: Int, row: Int) { self.column = column; self.row = row }
}

public struct MapDefinition: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let columns: Int
    public let rows: Int
    public let blockedCells: [GridCell]
    public let playerSpawn: GridCell
    public let enemyIds: [String]
    public let enemySpawns: [EnemySpawn]
}

public struct EnemySpawn: Codable, Equatable, Sendable {
    public let id: String
    public let enemyId: String
    public let cell: GridCell
}

public struct GameConfiguration: Codable, Equatable, Sendable {
    public let initialMapId: String
    public let maps: [MapDefinition]
    public let enemies: [EnemyDefinition]
}
