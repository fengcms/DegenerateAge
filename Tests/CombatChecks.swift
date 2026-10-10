import Foundation
import GameCore
import GameData

enum CombatChecks {
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func run() throws {
        let open = NavigationGrid(columns: 20, rows: 20, blocked: [])
        let origin = GridPosition(column: 10, row: 10)
        for x in -1...1 { for y in -1...1 where x != 0 || y != 0 {
            let direction = NavigationGrid.screenDirection(x: Double(x), y: Double(y))
            let end = open.move(from: origin, direction: direction, distance: 1)
            check(abs(end.distance(to: origin) - 1) < 0.000001, "八向世界速度不一致")
            let screenX = (end.column - end.row) - (origin.column - origin.row)
            let screenY = -(end.column + end.row) + (origin.column + origin.row)
            check(x == 0 ? abs(screenX) < 0.000001 : screenX * Double(x) > 0, "屏幕横向错误")
            check(y == 0 ? abs(screenY) < 0.000001 : screenY * Double(y) > 0, "屏幕纵向错误")
        }}
        let wall = NavigationGrid(columns: 8, rows: 8, blocked: Set((0..<8).map { GridCell(column: 4, row: $0) }))
        let stopped = wall.move(from: GridPosition(column: 2, row: 3), direction: WorldVector(1, 0), distance: 5)
        check(stopped.column < 3.5 && wall.canStand(stopped), "穿过墙体")
        check(wall.path(from: GridCell(column: 2, row: 3), to: GridCell(column: 6, row: 3)).isEmpty, "不可达目标返回了路径")
        let corner = NavigationGrid(columns: 4, rows: 4, blocked: [GridCell(column: 1, row: 0), GridCell(column: 0, row: 1)])
        check(!corner.canTraverse(from: GridCell(column: 0, row: 0), to: GridCell(column: 1, row: 1)), "斜切障碍")
        check(corner.path(from: GridCell(column: 0, row: 0), to: GridCell(column: 1, row: 1)).isEmpty, "寻路斜切障碍")
        let cornerEnd = corner.move(from: GridPosition(column: 0, row: 0), direction: WorldVector(1, 1), distance: 2)
        check(cornerEnd.column < 0.5 && cornerEnd.row < 0.5, "连续移动斜切障碍")
        let detour = NavigationGrid(columns: 8, rows: 8, blocked: [GridCell(column: 3, row: 3)])
        let route = detour.path(from: GridCell(column: 2, row: 3), to: GridCell(column: 4, row: 3))
        check(!route.isEmpty && !route.contains(GridCell(column: 3, row: 3)), "未绕开障碍")
        for pair in zip(route, route.dropFirst()) { check(detour.canTraverse(from: pair.0, to: pair.1), "路径包含无效边") }
        check(CombatSimulation.damage(attack: 20, defense: 10, multiplier: 1.5) == 25, "伤害公式错误")
        check(CombatSimulation.damage(attack: 0, defense: 100) == 1, "伤害下限错误")
        check(CombatSimulation.damage(attack: 20, defense: 10, multiplier: 1.5, critical: true) == 37, "暴击公式错误")

        var config = try fixture(hp: 22, attack: 0)
        var simulation = CombatSimulation(map: config.maps[0], definitions: config.enemies)
        let oldID = simulation.enemies[0].id
        simulation.selectTarget(oldID)
        var deathEvents = 0
        var hits = 0
        for _ in 0..<180 {
            let events = simulation.step(seconds: 1.0 / 60, attackHeld: true)
            for event in events {
                if case .monsterKilled = event { deathEvents += 1 }
                if case .damage(_, _, _, false) = event { hits += 1 }
            }
        }
        check(deathEvents == 1 && simulation.kills == 1, "死亡重复结算")
        check(hits == 2 && simulation.enemies[0].hp == 0, "普攻冷却或伤害错误")
        check(simulation.targetID == nil, "死目标未清理")
        let before = simulation.enemies[0].respawnRemaining
        let frozenHP = simulation.player.currentHP
        for _ in 0..<300 { _ = simulation.step(seconds: 1, attackHeld: true, paused: true) }
        check(simulation.enemies[0].respawnRemaining == before && simulation.player.currentHP == frozenHP, "暂停推进了模拟")
        for _ in 0..<600 { _ = simulation.step(seconds: 1.0 / 60) }
        check(simulation.enemies[0].alive && simulation.enemies[0].id != oldID, "刷新未生成新实例")
        simulation.selectTarget(oldID)
        check(simulation.targetID == nil, "旧实例仍可被选中")

        config = try fixture(hp: 40, attack: 1000)
        var lethal = CombatSimulation(map: config.maps[0], definitions: config.enemies)
        var playerDeaths = 0
        for _ in 0..<120 {
            for event in lethal.step(seconds: 1.0 / 60) { if case .playerDied = event { playerDeaths += 1 } }
        }
        check(lethal.player.currentHP == 0 && playerDeaths == 1, "玩家死亡重复或血量为负")
        let deadPosition = lethal.position
        _ = lethal.step(seconds: 1.0 / 60, screenX: 1, attackHeld: true)
        check(lethal.position == deadPosition && lethal.targetID == nil, "死亡后仍可操作")
        lethal.revive()
        check(lethal.player.currentHP == 100 && lethal.player.currentMP == 50, "复活未恢复生命法力")

        var limited = CombatSimulation(map: config.maps[0], definitions: config.enemies)
        let initial = limited.position
        _ = limited.step(seconds: 300, screenX: 1)
        check(limited.position.distance(to: initial) <= 0.100001, "卡顿导致角色瞬移")
        var pursuit = CombatSimulation(map: (try fixture(hp: 40, attack: 0)).maps[0], definitions: (try fixture(hp: 40, attack: 0)).enemies)
        var returned = false
        for _ in 0..<500 {
            _ = pursuit.step(seconds: 1.0 / 60, screenX: 1)
            if pursuit.enemies[0].phase == .returning { returned = true }
            check(pursuit.grid.canStand(pursuit.enemies[0].position), "怪物穿墙")
        }
        for _ in 0..<500 { _ = pursuit.step(seconds: 1.0 / 60) }
        check(returned && pursuit.enemies[0].position.distance(to: pursuit.enemies[0].home) < 0.2, "怪物超出追击范围未返回")
        var patrol = CombatSimulation(map: (try ConfigurationLoader.loadBundled()).maps[0], definitions: (try ConfigurationLoader.loadBundled()).enemies)
        let initialEnemy = patrol.enemies[0].position
        for _ in 0..<120 { _ = patrol.step(seconds: 1.0 / 60) }
        check(patrol.enemies[0].position != initialEnemy && patrol.enemies[0].phase != .attack, "未触发非战斗巡逻")
        let barrierConfig = try fixture(hp: 22, attack: 0, enemyCell: GridCell(column: 13, row: 13))
        var barrier = CombatSimulation(map: barrierConfig.maps[0], definitions: barrierConfig.enemies)
        barrier.selectTarget(barrier.enemies[0].id)
        for _ in 0..<600 {
            _ = barrier.step(seconds: 1.0 / 60, attackHeld: true)
            check(barrier.grid.canStand(barrier.position), "接近目标时玩家穿墙")
            check(barrier.grid.canStand(barrier.enemies[0].position), "追击时怪物穿墙")
        }
        check(barrier.kills >= 1, "无法绕过障碍击败怪物")
        print("PASS: 11 P1 check groups (movement, collision, corner, path, damage, kill/pause/respawn, death/revive, time clamp, leash, patrol, combat detour)")
    }
    private static func fixture(hp: Int, attack: Int, enemyCell: GridCell = GridCell(column: 17, row: 16)) throws -> GameConfiguration {
        let bundled = try ConfigurationLoader.loadBundled()
        let data = try JSONEncoder().encode(bundled)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var maps = object["maps"] as! [[String: Any]]
        maps[0]["enemySpawns"] = [["id": "test_wolf", "enemyId": "corrupted_wolf", "cell": ["column": enemyCell.column, "row": enemyCell.row]]]
        object["maps"] = maps
        var enemies = object["enemies"] as! [[String: Any]]
        enemies[0]["maxHP"] = hp; enemies[0]["attack"] = attack
        object["enemies"] = enemies
        return try ConfigurationLoader.decode(JSONSerialization.data(withJSONObject: object))
    }
}
