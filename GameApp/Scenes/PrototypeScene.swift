import SpriteKit
import GameCore

@MainActor
final class PrototypeScene: SKScene {
    private let map: MapDefinition
    private var simulation: CombatSimulation
    private let world = SKNode()
    private let viewCamera = SKCameraNode()
    private let playerNode = SKNode()
    private var enemyNodes: [String: SKNode] = [:]
    private var keys: Set<UInt16> = []
    private var configured = false
    private var lastTime: TimeInterval?
    private var accumulator: Double = 0
    private var hudRemaining: Double = 0
    private var simulationPaused = false
    var onSnapshot: ((SimulationSnapshot) -> Void)?
    var onToggleDebug: (() -> Void)?
    var onTogglePause: (() -> Void)?

    init(map: MapDefinition, simulation: CombatSimulation) {
        self.map = map; self.simulation = simulation
        super.init(size: CGSize(width: 1440, height: 900))
        scaleMode = .resizeFill
        backgroundColor = SKColor(red: 0.07, green: 0.09, blue: 0.12, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError("Use init(map:simulation:)") }
    func keyChanged(_ code: UInt16, down: Bool, repeating: Bool) {
        if code == 53 && down && !repeating { onTogglePause?(); return }
        if code == 99 && down && !repeating { onToggleDebug?(); return }
        guard !simulationPaused else { return }
        if down { keys.insert(code) } else { keys.remove(code) }
    }
    func clearInput() { keys = []; simulation.cancelAction() }
    func setSimulationPaused(_ paused: Bool) {
        simulationPaused = paused
        isPaused = paused
        clearInput(); lastTime = nil; accumulator = 0
        if !paused { view?.window?.makeFirstResponder(view) }
    }
    func revive() { simulation.revive(); clearInput(); syncEntities(); onSnapshot?(simulation.snapshot); view?.window?.makeFirstResponder(view) }
    override func didMove(to view: SKView) {
        guard !configured else { return }
        configured = true
        addChild(world); addChild(viewCamera); camera = viewCamera
        for row in 0..<map.rows { for column in 0..<map.columns {
            let cell = GridCell(column: column, row: row)
            let tile = SKShapeNode(path: diamond())
            tile.position = IsometricProjection.point(column: Double(column), row: Double(row))
            tile.fillColor = SKColor(red: 0.16, green: (column + row).isMultiple(of: 2) ? 0.25 : 0.28, blue: 0.23, alpha: 1)
            tile.strokeColor = SKColor(white: 0.08, alpha: 1)
            tile.lineWidth = 1; tile.zPosition = -10000
            world.addChild(tile)
            if simulation.grid.blocked.contains(cell) {
                let obstacle = SKShapeNode(rectOf: CGSize(width: 45, height: 45), cornerRadius: 5)
                let point = tile.position
                obstacle.position = CGPoint(x: point.x, y: point.y + 15)
                obstacle.fillColor = SKColor(white: 0.36, alpha: 1)
                obstacle.strokeColor = SKColor(white: 0.55, alpha: 1)
                obstacle.zPosition = -point.y
                world.addChild(obstacle)
            }
        }}
        makeActor(playerNode, color: .systemTeal, name: "守护者")
        world.addChild(playerNode)
        for enemy in simulation.enemies {
            let node = SKNode()
            makeActor(node, color: .systemOrange, name: enemy.definition.name)
            enemyNodes[enemy.spawnID] = node; world.addChild(node)
        }
        viewCamera.position = point(simulation.position)
        syncEntities(); fitCamera()
    }
    override func didChangeSize(_ oldSize: CGSize) { fitCamera() }
    private func fitCamera() { viewCamera.setScale(1) }
    override func mouseDown(with event: NSEvent) {
        guard !simulationPaused, simulation.player.currentHP > 0 else { return }
        let location = event.location(in: world)
        let selected = simulation.enemies.filter(\.alive).min { a, b in
            let pa = point(a.position), pb = point(b.position)
            return hypot(location.x - pa.x, location.y - pa.y - 20) < hypot(location.x - pb.x, location.y - pb.y - 20)
        }
        if let selected {
            let p = point(selected.position)
            if hypot(location.x - p.x, location.y - p.y - 20) < 38 { simulation.selectTarget(selected.id) }
            else { simulation.selectTarget(nil) }
        }
        onSnapshot?(simulation.snapshot)
    }
    override func update(_ currentTime: TimeInterval) {
        guard !simulationPaused else { lastTime = nil; return }
        guard let previous = lastTime else { lastTime = currentTime; return }
        lastTime = currentTime
        let elapsed = max(0, min(currentTime - previous, 0.1))
        accumulator += elapsed
        let dt = 1.0 / 60
        while accumulator >= dt {
            let x = (keys.contains(2) ? 1.0 : 0) - (keys.contains(0) ? 1.0 : 0)
            let y = (keys.contains(13) ? 1.0 : 0) - (keys.contains(1) ? 1.0 : 0)
            let events = simulation.step(seconds: dt, screenX: x, screenY: y, attackHeld: keys.contains(49))
            for event in events { display(event) }
            accumulator -= dt
        }
        syncEntities()
        updateCamera(elapsed: elapsed)
        hudRemaining -= elapsed
        if hudRemaining <= 0 { onSnapshot?(simulation.snapshot); hudRemaining = 0.1 }
    }
    private func updateCamera(elapsed: Double) {
        let desired = point(simulation.position)
        let center = IsometricProjection.point(column: Double(map.columns - 1) / 2, row: Double(map.rows - 1) / 2)
        let halfWidth = CGFloat(map.columns + map.rows) * 16
        let halfHeight = CGFloat(map.columns + map.rows) * 8
        let marginX = max(0, halfWidth - size.width / 2)
        let marginY = max(0, halfHeight - size.height / 2)
        // Clamp to the world bounds; diamond corners retain the neutral background.
        let target = CGPoint(x: min(center.x + marginX, max(center.x - marginX, desired.x)), y: min(center.y + marginY, max(center.y - marginY, desired.y)))
        let blend = 1 - exp(-8 * elapsed)
        viewCamera.position.x += (target.x - viewCamera.position.x) * blend
        viewCamera.position.y += (target.y - viewCamera.position.y) * blend
    }
    private func syncEntities() {
        playerNode.position = point(simulation.position)
        playerNode.zPosition = -playerNode.position.y
        playerNode.alpha = simulation.player.currentHP > 0 ? 1 : 0.35
        updateBar(playerNode, hp: simulation.player.currentHP, maxHP: 100)
        for enemy in simulation.enemies {
            guard let node = enemyNodes[enemy.spawnID] else { continue }
            node.isHidden = !enemy.alive
            node.position = point(enemy.position); node.zPosition = -node.position.y
            updateBar(node, hp: enemy.hp, maxHP: enemy.definition.maxHP)
            (node.childNode(withName: "body") as? SKShapeNode)?.strokeColor = simulation.targetID == enemy.id ? .yellow : .white
        }
    }
    private func makeActor(_ node: SKNode, color: SKColor, name: String) {
        let shadow = SKShapeNode(ellipseOf: CGSize(width: 32, height: 12))
        shadow.fillColor = SKColor(white: 0, alpha: 0.4); shadow.strokeColor = .clear
        node.addChild(shadow)
        let body = SKShapeNode(rectOf: CGSize(width: 22, height: 38), cornerRadius: 5)
        body.name = "body"; body.position.y = 19; body.fillColor = color; body.strokeColor = .white
        node.addChild(body)
        let label = SKLabelNode(text: name)
        label.fontName = "Helvetica"; label.fontSize = 12; label.position.y = 57
        node.addChild(label)
        let background = SKSpriteNode(color: .darkGray, size: CGSize(width: 34, height: 4))
        background.position.y = 47; node.addChild(background)
        let bar = SKSpriteNode(color: .systemGreen, size: CGSize(width: 34, height: 4))
        bar.name = "hp"; bar.anchorPoint = CGPoint(x: 0, y: 0.5); bar.position = CGPoint(x: -17, y: 47)
        node.addChild(bar)
    }
    private func updateBar(_ node: SKNode, hp: Int, maxHP: Int) { node.childNode(withName: "hp")?.xScale = CGFloat(hp) / CGFloat(maxHP) }
    private func display(_ event: CombatEvent) {
        switch event {
        case let .damage(position, amount, critical, player):
            let label = SKLabelNode(text: critical ? "暴击 \(amount)" : "\(amount)")
            label.fontName = "Helvetica-Bold"; label.fontSize = critical ? 24 : 19
            label.fontColor = player ? .systemRed : (critical ? .yellow : .white)
            let p = point(position); label.position = CGPoint(x: p.x, y: p.y + 65); label.zPosition = 10000
            world.addChild(label)
            label.run(.sequence([.group([.moveBy(x: 0, y: 32, duration: 0.65), .fadeOut(withDuration: 0.65)]), .removeFromParent()]))
            let actor = player ? playerNode : simulation.enemies.first(where: { $0.position == position }).flatMap { enemyNodes[$0.spawnID] }
            actor?.childNode(withName: "body")?.run(.sequence([.fadeAlpha(to: 0.35, duration: 0.06), .fadeAlpha(to: 1, duration: 0.12)]))
        case .monsterKilled: break
        case .playerDied: clearInput()
        }
    }
    private func point(_ position: GridPosition) -> CGPoint { IsometricProjection.point(column: position.column, row: position.row) }
    private func diamond() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: 16)); path.addLine(to: CGPoint(x: 32, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -16)); path.addLine(to: CGPoint(x: -32, y: 0)); path.closeSubpath()
        return path
    }
}
