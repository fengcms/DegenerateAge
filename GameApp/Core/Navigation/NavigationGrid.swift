import Foundation

public struct WorldVector: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(_ x: Double, _ y: Double) { self.x = x; self.y = y }
    public var length: Double { hypot(x, y) }
    public var normalized: WorldVector { length > 0 ? WorldVector(x / length, y / length) : WorldVector(0, 0) }
}

public extension GridPosition {
    func distance(to other: GridPosition) -> Double { hypot(column - other.column, row - other.row) }
    var cell: GridCell { GridCell(column: Int(floor(column + 0.5)), row: Int(floor(row + 0.5))) }
}

public struct NavigationGrid: Sendable {
    public let columns: Int
    public let rows: Int
    public let blocked: Set<GridCell>
    public init(columns: Int, rows: Int, blocked: Set<GridCell>) {
        self.columns = columns; self.rows = rows; self.blocked = blocked
    }
    public init(map: MapDefinition) { self.init(columns: map.columns, rows: map.rows, blocked: Set(map.blockedCells)) }
    public func walkable(_ cell: GridCell) -> Bool {
        cell.column >= 0 && cell.column < columns && cell.row >= 0 && cell.row < rows && !blocked.contains(cell)
    }
    // Foot collision radius in world/grid units, independent of sprite artwork.
    public func canStand(_ point: GridPosition, radius: Double = 0.18) -> Bool {
        guard point.column.isFinite && point.row.isFinite else { return false }
        for row in Int(floor(point.row - radius + 0.5))...Int(floor(point.row + radius + 0.5)) {
            for column in Int(floor(point.column - radius + 0.5))...Int(floor(point.column + radius + 0.5)) {
                if !walkable(GridCell(column: column, row: row)) { return false }
            }
        }
        return true
    }
    public func canTraverse(from: GridCell, to: GridCell) -> Bool {
        guard walkable(from), walkable(to) else { return false }
        let dx = to.column - from.column, dy = to.row - from.row
        guard abs(dx) <= 1 && abs(dy) <= 1 else { return false }
        if dx != 0 && dy != 0 {
            return walkable(GridCell(column: from.column + dx, row: from.row)) &&
                walkable(GridCell(column: from.column, row: from.row + dy))
        }
        return true
    }
    public func move(from start: GridPosition, direction: WorldVector, distance: Double) -> GridPosition {
        guard distance > 0, direction.length > 0 else { return start }
        let unit = direction.normalized
        let steps = max(1, Int(ceil(distance / 0.08)))
        let step = distance / Double(steps)
        var point = start
        for _ in 0..<steps {
            let next = GridPosition(column: point.column + unit.x * step, row: point.row + unit.y * step)
            if canStand(next) && canTraverse(from: point.cell, to: next.cell) { point = next; continue }
            // Slide along one axis, never through a blocked diagonal corner.
            let horizontal = GridPosition(column: next.column, row: point.row)
            let vertical = GridPosition(column: point.column, row: next.row)
            if canStand(horizontal) && canTraverse(from: point.cell, to: horizontal.cell) { point = horizontal }
            else if canStand(vertical) && canTraverse(from: point.cell, to: vertical.cell) { point = vertical }
        }
        return point
    }
    public func lineClear(from start: GridPosition, to end: GridPosition) -> Bool {
        let steps = max(1, Int(ceil(start.distance(to: end) / 0.08)))
        var previous = start
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let point = GridPosition(column: start.column + (end.column - start.column) * t, row: start.row + (end.row - start.row) * t)
            if !canStand(point, radius: 0) || !canTraverse(from: previous.cell, to: point.cell) { return false }
            previous = point
        }
        return true
    }
    // A* with octile heuristic; replanning is throttled by the simulation.
    public func path(from start: GridCell, to end: GridCell) -> [GridCell] {
        guard walkable(start), walkable(end) else { return [] }
        if start == end { return [start] }
        func heuristic(_ a: GridCell) -> Double {
            let x = Double(abs(a.column - end.column)), y = Double(abs(a.row - end.row))
            return max(x, y) + (sqrt(2) - 1) * min(x, y)
        }
        var open = [start], closed: Set<GridCell> = [], costs = [start: 0.0], previous: [GridCell: GridCell] = [:]
        while !open.isEmpty {
            let index = open.indices.min { (costs[open[$0]] ?? .infinity) + heuristic(open[$0]) < (costs[open[$1]] ?? .infinity) + heuristic(open[$1]) }!
            let current = open.remove(at: index)
            if current == end {
                var result = [end], cursor = end
                while let parent = previous[cursor] { result.append(parent); cursor = parent }
                return result.reversed()
            }
            closed.insert(current)
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let next = GridCell(column: current.column + dx, row: current.row + dy)
                guard !closed.contains(next), canTraverse(from: current, to: next) else { continue }
                let cost = costs[current, default: 0] + (dx != 0 && dy != 0 ? sqrt(2) : 1)
                if cost < costs[next, default: .infinity] {
                    costs[next] = cost; previous[next] = current
                    if !open.contains(next) { open.append(next) }
                }
            }}
        }
        return []
    }
    // Inverse of (screenX = 32(c-r), screenY = -16(c+r)), then world normalization.
    public static func screenDirection(x: Double, y: Double) -> WorldVector {
        WorldVector(x / 64 - y / 32, -x / 64 - y / 32).normalized
    }
}
