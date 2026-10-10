import Foundation
import GameCore

// P0 最小快照；P2 实现持久化时补齐装备、任务、设置及迁移。
public struct GameSave: Codable, Equatable, Sendable {
    public var schemaVersion: Int = 1
    public var slotId: Int
    public var savedAt: Date
    public var player: PlayerState
    public var mapId: String
    public var position: GridPosition
    public init(slotId: Int, savedAt: Date = Date(), player: PlayerState, mapId: String, position: GridPosition) {
        self.slotId = slotId; self.savedAt = savedAt; self.player = player
        self.mapId = mapId; self.position = position
    }
}
