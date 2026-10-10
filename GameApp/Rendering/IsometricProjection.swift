import CoreGraphics
import GameCore

// SpriteKit Y 轴向上；row/column 增大时，地图在屏幕上向下延伸。
enum IsometricProjection {
    static let tileWidth: CGFloat = 64
    static let tileHeight: CGFloat = 32
    static func point(column: Double, row: Double) -> CGPoint {
        CGPoint(x: (column - row) * tileWidth / 2, y: -(column + row) * tileHeight / 2)
    }
}
