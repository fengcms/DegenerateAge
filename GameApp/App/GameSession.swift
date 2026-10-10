import SwiftUI
import GameCore
import GameData

@MainActor
final class GameSession: ObservableObject {
    let scene: PrototypeScene?
    let errorMessage: String?
    @Published var snapshot: SimulationSnapshot?
    @Published var paused = false { didSet { updatePause() } }
    @Published var debugVisible = false
    private var inactive = false
    init() {
        do {
            let configuration = try ConfigurationLoader.loadBundled()
            guard let map = configuration.maps.first(where: { $0.id == configuration.initialMapId }) else {
                throw ConfigurationError(issues: ["找不到初始地图"])
            }
            let simulation = CombatSimulation(map: map, definitions: configuration.enemies)
            let scene = PrototypeScene(map: map, simulation: simulation)
            self.scene = scene
            snapshot = simulation.snapshot
            errorMessage = nil
            scene.onSnapshot = { [weak self] in self?.snapshot = $0 }
            scene.onToggleDebug = { [weak self, weak scene] in
                guard let self else { return }
                self.debugVisible.toggle()
                scene?.view?.showsFPS = self.debugVisible
                scene?.view?.showsNodeCount = self.debugVisible
            }
            scene.onTogglePause = { [weak self] in self?.paused.toggle() }
        } catch {
            scene = nil; errorMessage = error.localizedDescription
        }
    }
    func setActive(_ active: Bool) { inactive = !active; updatePause() }
    private func updatePause() { scene?.setSimulationPaused(paused || inactive) }
    func revive() { scene?.revive() }
}
