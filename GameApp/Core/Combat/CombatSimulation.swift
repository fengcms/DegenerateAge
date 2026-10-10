import Foundation

public enum EnemyPhase: String, Sendable { case idle, patrol, chase, attack, returning, dead }
public struct EnemyRuntime: Sendable {
    public let spawnID: String
    fileprivate(set) var generation = 0
    public var id: String { "\(spawnID):\(generation)" }
    public let definition: EnemyDefinition
    public let home: GridPosition
    public var position: GridPosition
    public var hp: Int
    public var phase: EnemyPhase = .idle
    public var cooldown: Double = 0
    public var respawnRemaining: Double = 0
    var decisionRemaining: Double = 0
    var path: [GridCell] = []
    var patrolIndex = 0
    var idleRemaining: Double = 1
    public var alive: Bool { hp > 0 }
}
public enum CombatEvent: Sendable {
    case damage(position: GridPosition, amount: Int, critical: Bool, player: Bool)
    case monsterKilled(id: String)
    case playerDied
}
public struct SimulationSnapshot: Sendable {
    public let hp: Int
    public let position: GridPosition
    public let kills: Int
    public let targetName: String?
    public let targetHP: Int?
    public let targetPhase: String?
    public let status: String
    public let targetID: String?
    public let pathNodes: Int
    public let enemyCount: Int
}
public struct CombatSimulation: Sendable {
    public private(set) var player = PlayerState()
    public private(set) var position: GridPosition
    public private(set) var enemies: [EnemyRuntime]
    public private(set) var targetID: String?
    public private(set) var kills = 0
    public private(set) var status = "点击野狼选择目标，按住空格攻击"
    public let grid: NavigationGrid
    private let spawn: GridPosition
    private var playerCooldown: Double = 0
    private var approach = false
    private var approachPath: [GridCell] = []
    private var approachReplan: Double = 0
    private var randomState: UInt64

    public init(map: MapDefinition, definitions: [EnemyDefinition], seed: UInt64 = 3172) {
        grid = NavigationGrid(map: map)
        spawn = GridPosition(column: Double(map.playerSpawn.column), row: Double(map.playerSpawn.row))
        position = spawn
        randomState = seed
        enemies = map.enemySpawns.compactMap { entry in
            guard let definition = definitions.first(where: { $0.id == entry.enemyId }) else { return nil }
            let home = GridPosition(column: Double(entry.cell.column), row: Double(entry.cell.row))
            return EnemyRuntime(spawnID: entry.id, definition: definition, home: home, position: home, hp: definition.maxHP)
        }
    }
    public var snapshot: SimulationSnapshot {
        let target = enemies.first { $0.id == targetID && $0.alive }
        return SimulationSnapshot(hp: player.currentHP, position: position, kills: kills, targetName: target?.definition.name, targetHP: target?.hp, targetPhase: target?.phase.rawValue, status: status, targetID: targetID, pathNodes: approachPath.count + enemies.reduce(0) { $0 + $1.path.count }, enemyCount: enemies.filter(\.alive).count)
    }
    public mutating func selectTarget(_ id: String?) {
        guard player.currentHP > 0 else { return }
        targetID = enemies.first { $0.id == id && $0.alive }?.id
        approach = targetID != nil
        approachPath = []; approachReplan = 0
    }
    public mutating func cancelAction() { approach = false; approachPath = [] }
    public mutating func revive() {
        guard player.currentHP == 0 else { return }
        player.currentHP = 100; player.currentMP = 50; position = spawn
        targetID = nil; playerCooldown = 0; cancelAction()
        for i in enemies.indices where enemies[i].alive {
            enemies[i].position = enemies[i].home; enemies[i].phase = .idle
            enemies[i].path = []; enemies[i].cooldown = 0; enemies[i].decisionRemaining = 0
        }
        status = "已返回营地复活"
    }
    public static func damage(attack: Int, defense: Int, multiplier: Double = 1, critical: Bool = false) -> Int {
        let base = max(1, Int(floor(Double(attack) * multiplier - Double(defense) * 0.5)))
        return critical ? Int(floor(Double(base) * 1.5)) : base
    }
    public mutating func step(seconds: Double, screenX: Double = 0, screenY: Double = 0, attackHeld: Bool = false, paused: Bool = false) -> [CombatEvent] {
        guard !paused, seconds > 0, seconds.isFinite else { return [] }
        let dt = min(seconds, 1.0 / 30)
        var events: [CombatEvent] = []
        playerCooldown = max(0, playerCooldown - dt)
        if player.currentHP > 0 {
            let direction = NavigationGrid.screenDirection(x: screenX, y: screenY)
            if direction.length > 0 {
                cancelAction()
                position = grid.move(from: position, direction: direction, distance: 3 * dt)
                status = "手动移动"
            }
            if let index = enemies.firstIndex(where: { $0.id == targetID && $0.alive }) {
                let target = enemies[index]
                let inRange = position.distance(to: target.position) <= 1.2 && grid.lineClear(from: position, to: target.position)
                if !inRange && (approach || attackHeld) && direction.length == 0 {
                    approachReplan -= dt
                    if approachReplan <= 0 {
                        approachPath = Array(grid.path(from: position.cell, to: target.position.cell).dropFirst())
                        approachReplan = 0.4
                    }
                    if let next = approachPath.first {
                        let destination = GridPosition(column: Double(next.column), row: Double(next.row))
                        let vector = WorldVector(destination.column - position.column, destination.row - position.row)
                        position = grid.move(from: position, direction: vector, distance: min(3 * dt, vector.length))
                        if position.distance(to: destination) < 0.08 { approachPath.removeFirst() }
                        status = "接近目标"
                    } else { status = "目标暂时不可达" }
                }
                if inRange && (attackHeld || approach) && playerCooldown <= 0 {
                    randomState = randomState &* 6364136223846793005 &+ 1442695040888963407
                    let critical = Double(randomState >> 11) / 9007199254740992 < 0.05
                    let amount = Self.damage(attack: 12, defense: target.definition.defense, critical: critical)
                    enemies[index].hp = max(0, target.hp - amount)
                    playerCooldown = 0.8; approach = false
                    events.append(.damage(position: target.position, amount: amount, critical: critical, player: false))
                    status = critical ? "暴击！" : "普通斩击"
                    if enemies[index].hp == 0 {
                        enemies[index].phase = .dead
                        enemies[index].path = []
                        enemies[index].respawnRemaining = target.definition.respawnSeconds
                        kills += 1
                        events.append(.monsterKilled(id: target.id))
                        targetID = nil; cancelAction()
                        status = "腐化野狼已击败"
                    }
                }
            } else if targetID != nil { targetID = nil; cancelAction() }
        }
        for index in enemies.indices {
            var enemy = enemies[index]
            if !enemy.alive {
                enemy.respawnRemaining -= dt
                if enemy.respawnRemaining <= 0 {
                    enemy.generation += 1
                    enemy.hp = enemy.definition.maxHP; enemy.position = enemy.home
                    enemy.phase = .idle; enemy.cooldown = 0; enemy.decisionRemaining = 0; enemy.idleRemaining = 1
                }
                enemies[index] = enemy; continue
            }
            enemy.cooldown = max(0, enemy.cooldown - dt)
            enemy.decisionRemaining -= dt
            let distance = enemy.position.distance(to: position)
            let outsideLeash = enemy.position.distance(to: enemy.home) > enemy.definition.leashRadius || position.distance(to: enemy.home) > enemy.definition.leashRadius
            if enemy.phase == .returning || outsideLeash || player.currentHP == 0 {
                enemy.phase = .returning
                navigate(&enemy, to: enemy.home, dt: dt)
                if enemy.position.distance(to: enemy.home) < 0.15 {
                    enemy.phase = .idle; enemy.hp = enemy.definition.maxHP; enemy.idleRemaining = 1
                }
            } else if distance <= enemy.definition.aggroRadius || enemy.phase == .chase || enemy.phase == .attack || enemy.id == targetID {
                if distance <= enemy.definition.attackRange && grid.lineClear(from: enemy.position, to: position) {
                    enemy.phase = .attack; enemy.path = []
                    if enemy.cooldown <= 0 && player.currentHP > 0 {
                        let amount = Self.damage(attack: enemy.definition.attack, defense: 5)
                        player.currentHP = max(0, player.currentHP - amount)
                        enemy.cooldown = enemy.definition.attackInterval
                        events.append(.damage(position: position, amount: amount, critical: false, player: true))
                        if player.currentHP == 0 {
                            targetID = nil; cancelAction(); status = "守护者倒下了"
                            events.append(.playerDied)
                        }
                    }
                } else { enemy.phase = .chase; navigate(&enemy, to: position, dt: dt) }
            } else {
                enemy.idleRemaining -= dt
                if enemy.idleRemaining <= 0 {
                    enemy.phase = .patrol
                    let offsets = [(1.0, 0.0), (0.0, 1.0), (-1.0, 0.0), (0.0, -1.0)]
                    let offset = offsets[enemy.patrolIndex % offsets.count]
                    let destination = GridPosition(column: enemy.home.column + offset.0, row: enemy.home.row + offset.1)
                    navigate(&enemy, to: destination, dt: dt)
                    if enemy.position.distance(to: destination) < 0.15 || !grid.canStand(destination) {
                        enemy.patrolIndex += 1; enemy.idleRemaining = 1; enemy.phase = .idle; enemy.path = []; enemy.decisionRemaining = 0
                    }
                }
            }
            enemies[index] = enemy
        }
        return events
    }
    private func navigate(_ enemy: inout EnemyRuntime, to destination: GridPosition, dt: Double) {
        if enemy.decisionRemaining <= 0 {
            enemy.path = Array(grid.path(from: enemy.position.cell, to: destination.cell).dropFirst())
            // Within the same cell, still converge to the destination.
            if enemy.path.isEmpty && enemy.position.cell == destination.cell { enemy.path = [destination.cell] }
            enemy.decisionRemaining = 0.4
        }
        guard let cell = enemy.path.first else { return }
        let point = cell == destination.cell ? destination : GridPosition(column: Double(cell.column), row: Double(cell.row))
        let vector = WorldVector(point.column - enemy.position.column, point.row - enemy.position.row)
        enemy.position = grid.move(from: enemy.position, direction: vector, distance: min(enemy.definition.movementSpeed * dt, vector.length))
        if enemy.position.distance(to: point) < 0.08 { enemy.path.removeFirst() }
    }
}
