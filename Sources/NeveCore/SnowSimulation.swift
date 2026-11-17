import Foundation
import CoreGraphics

public enum SnowWindDirection: String, Codable {
    case vertical
    case lateral
}

public struct SnowSettings: Codable, Equatable {
    public var density = 0.65
    public var speed = 0.75
    public var wind = 0.0
    public var windDirection: SnowWindDirection = .vertical
    public var maxDepth = 24.0
    public var accumulation = true
    public var showSnowman = true
    public var automaticPlough = true
    public var horizontalWind: Double { windDirection == .vertical ? 0 : wind }
    public init() {}

    private enum CodingKeys: String, CodingKey {
        case density, speed, wind, windDirection, maxDepth, accumulation, showSnowman, automaticPlough
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        density = min(1.5, max(0.15, try values.decodeIfPresent(Double.self, forKey: .density) ?? density))
        speed = min(2, max(0.1, try values.decodeIfPresent(Double.self, forKey: .speed) ?? speed))
        wind = min(1.5, max(-1.5, try values.decodeIfPresent(Double.self, forKey: .wind) ?? wind))
        // Older preferences retain their appearance and start with the requested downward snowfall.
        windDirection = try values.decodeIfPresent(SnowWindDirection.self, forKey: .windDirection) ?? .vertical
        maxDepth = min(45, max(8, try values.decodeIfPresent(Double.self, forKey: .maxDepth) ?? maxDepth))
        accumulation = try values.decodeIfPresent(Bool.self, forKey: .accumulation) ?? accumulation
        showSnowman = try values.decodeIfPresent(Bool.self, forKey: .showSnowman) ?? showSnowman
        automaticPlough = try values.decodeIfPresent(Bool.self, forKey: .automaticPlough) ?? automaticPlough
    }
}

public struct Span: Equatable {
    public var lower: Double
    public var upper: Double
    public init(_ lower: Double, _ upper: Double) { self.lower = lower; self.upper = upper }
    public func contains(_ x: Double) -> Bool { x >= lower && x <= upper }
}

public struct WindowGeometry {
    public var id: Int
    public var rect: CGRect
    public init(id: Int, rect: CGRect) { self.id = id; self.rect = rect }
}

public enum SnowGeometry {
    // Quartz has its origin at the primary display's top left. Each scene is flipped, y down.
    public static func localRect(quartz: CGRect, screen: CGRect, primaryHeight: Double) -> CGRect {
        CGRect(x: quartz.minX - screen.minX,
               y: quartz.minY + screen.maxY - primaryHeight,
               width: quartz.width, height: quartz.height)
    }

    public static func subtract(_ spans: [Span], covered: Span) -> [Span] {
        spans.flatMap { span -> [Span] in
            if covered.upper <= span.lower || covered.lower >= span.upper { return [span] }
            var result: [Span] = []
            if covered.lower > span.lower { result.append(Span(span.lower, covered.lower)) }
            if covered.upper < span.upper { result.append(Span(covered.upper, span.upper)) }
            return result
        }
    }

    // Input order is front to back, matching CGWindowListCopyWindowInfo.
    public static func exposedTop(of window: WindowGeometry, inFront: [WindowGeometry], width: Double) -> [Span] {
        var spans = [Span(max(0, window.rect.minX), min(width, window.rect.maxX))]
            .filter { $0.upper > $0.lower }
        for front in inFront where front.rect.minY <= window.rect.minY + 1 && front.rect.maxY > window.rect.minY {
            spans = subtract(spans, covered: Span(front.rect.minX, front.rect.maxX))
        }
        return spans.filter { $0.upper - $0.lower > 3 }
    }
}

public struct SnowSurface {
    public let id: Int
    public var rect: CGRect
    public var spans: [Span]
    public var depths: [Double]
    public var spacing: Double { rect.width / Double(max(1, depths.count - 1)) }
    public var y: Double { rect.minY }
    public func contains(_ x: Double) -> Bool { spans.contains { $0.contains(x) } }
    public func depth(at x: Double) -> Double {
        guard !depths.isEmpty, rect.width > 0 else { return 0 }
        let t = min(Double(depths.count - 1), max(0, (x - rect.minX) / spacing))
        let i = Int(t), j = min(i + 1, depths.count - 1)
        return depths[i] * (1 - (t - Double(i))) + depths[j] * (t - Double(i))
    }
    public func height(at x: Double) -> Double { y - depth(at: x) }

    public func capacity(at x: Double, maximum: Double) -> Double {
        let local = max(0, min(rect.width, x - rect.minX))
        let phase = Double(id % 997) * 0.37
        func noise(_ distance: Double, _ salt: Double) -> Double {
            let t = local / distance + phase + salt
            let cell = floor(t), f = t - cell
            func hash(_ value: Double) -> Double {
                let n = sin(value * 127.1 + phase * 19.19) * 43758.5453
                return n - floor(n)
            }
            let blend = f * f * (3 - 2 * f)
            return hash(cell) * (1 - blend) + hash(cell + 1) * blend
        }
        let hills = 0.42 + 0.35 * noise(66, 0) + 0.17 * noise(23, 7) + 0.06 * noise(8, 13)
        let edge = min(local, rect.width - local)
        let taper = id == SnowSimulation.groundID ? 1 : min(1, 0.12 + max(0, edge) / 16)
        return maximum * hills * taper
    }
}

public struct Snowplough {
    public let id: Int
    public let surfaceID: Int
    public var localX: Double
    public var route: Span
    public let scale: Double
}

public struct Flake {
    public var position: CGPoint
    public var velocity: CGVector
    public var radius: Double
    public var opacity: Double
    public var phase: Double
    public var debris: Bool
    public var life: Double
}

private struct SnowRandom {
    var state: UInt64
    mutating func unit() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double(state >> 11) / Double(UInt64(1) << 53)
    }
    mutating func value(_ low: Double, _ high: Double) -> Double { low + (high - low) * unit() }
}

public final class SnowSimulation {
    public var settings: SnowSettings
    public let size: CGSize
    public private(set) var surfaces: [SnowSurface] = []
    public private(set) var flakes: [Flake] = []
    public private(set) var ploughs: [Snowplough] = []
    public private(set) var geometryRevision = 0
    public var ploughX: Double? { ploughs.first { $0.surfaceID == Self.groundID }?.localX }
    public private(set) var time = 0.0
    private var random: SnowRandom
    private var nextPloughID = 1
    private var previousVelocities: [Int: CGVector] = [:]
    private var nextPlough = 14.0
    public static let groundID = -1

    public init(size: CGSize, settings: SnowSettings = SnowSettings(), seed: UInt64 = 2026) {
        self.size = size; self.settings = settings; self.random = SnowRandom(state: seed)
        updateWindows([])
        replenish(initial: true, quality: 1)
    }

    public func updateWindows(_ windows: [WindowGeometry], elapsed: Double = 1.0 / 60) {
        let previous = Dictionary(uniqueKeysWithValues: surfaces.map { ($0.id, $0) })
        var result: [SnowSurface] = []
        var changed = false
        for (index, window) in windows.enumerated() where window.rect.minY >= 3 && window.rect.minY < size.height - 10 {
            guard window.rect.width.isFinite, window.rect.width > 0 else { continue }
            let spans = SnowGeometry.exposedTop(of: window, inFront: Array(windows.prefix(index)), width: size.width)
            guard !spans.isEmpty else { continue }
            let count = max(2, Int(min(2047, window.rect.width / 4)) + 1)
            var surface = SnowSurface(id: window.id, rect: window.rect, spans: spans,
                depths: previous[window.id]?.depths ?? Array(repeating: 0, count: count))
            if let old = previous[window.id] {
                let dx = window.rect.minX - old.rect.minX, dy = window.rect.minY - old.y
                let velocity = CGVector(dx: dx / max(elapsed, 1.0 / 120), dy: dy / max(elapsed, 1.0 / 120))
                let prior = previousVelocities[window.id] ?? .zero
                let shook = hypot(velocity.dx, velocity.dy) > 550 && hypot(prior.dx, prior.dy) > 400 &&
                    velocity.dx * prior.dx + velocity.dy * prior.dy < -100_000
                if shook { scatter(old, dx: velocity.dx * 0.4) }
                if old.rect.width != window.rect.width {
                    surface.depths = Array(repeating: 0, count: count)
                    for i in surface.depths.indices {
                        // Resampling is needed only on resize; ordinary movement shares the existing storage.
                        let localX = Double(i) * surface.spacing
                        surface.depths[i] = old.depth(at: old.rect.minX + localX)
                    }
                }
                if shook { for i in surface.depths.indices { surface.depths[i] *= 0.35 } }
                previousVelocities[window.id] = velocity
                changed = changed || old.rect != window.rect || old.spans != spans
            } else { changed = true }
            result.append(surface)
        }
        let groundRect = CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)
        let ground = previous[Self.groundID] ?? SnowSurface(id: Self.groundID, rect: groundRect,
            spans: [Span(0, size.width)], depths: Array(repeating: 0, count: max(2, Int(size.width / 4) + 1)))
        result.append(ground)
        for old in surfaces where old.id != Self.groundID && !result.contains(where: { $0.id == old.id }) {
            scatter(old, dx: 0)
            previousVelocities.removeValue(forKey: old.id); changed = true
        }
        surfaces = result.sorted { $0.y < $1.y }
        if changed { geometryRevision &+= 1 }
        ploughs.removeAll { plough in !surfaces.contains { $0.id == plough.surfaceID } }
    }

    private func freshFlake(initial: Bool) -> Flake {
        let depth = random.unit()
        return Flake(position: CGPoint(x: random.value(0, size.width), y: initial ? random.value(0, size.height) : random.value(-45, -3)),
            velocity: CGVector(dx: random.value(-8, 8), dy: 22 + depth * 58),
            radius: 0.7 + depth * 2.1, opacity: 0.3 + depth * 0.65,
            phase: random.value(0, .pi * 2), debris: false, life: 10)
    }

    private func replenish(initial: Bool, quality: Double) {
        let target = Int(min(1300, max(30, size.width * size.height / 2400 * settings.density * quality)))
        let current = flakes.reduce(0) { $0 + ($1.debris ? 0 : 1) }
        if current < target { for _ in current..<target { flakes.append(freshFlake(initial: initial)) } }
        if current > target {
            var excess = current - target
            flakes.removeAll { flake in
                if !flake.debris && excess > 0 { excess -= 1; return true }; return false
            }
        }
    }

    public func step(_ delta: Double, quality: Double = 1) {
        let dt = max(0, min(delta, 0.05))
        guard dt > 0 else { return }
        time += dt
        replenish(initial: false, quality: quality)
        for i in flakes.indices {
            var f = flakes[i]
            let old = f.position
            if f.debris {
                f.velocity.dy += 260 * dt; f.velocity.dx *= pow(0.6, dt)
                f.position.x += f.velocity.dx * dt
                f.position.y += f.velocity.dy * dt
                f.life -= dt
            } else {
                let sway = settings.windDirection == .vertical ? 0.2 : 1
                f.position.x += (settings.horizontalWind * 65 + (f.velocity.dx + sin(time * 0.8 + f.phase) * 15) * sway) * dt
                f.position.y += f.velocity.dy * (0.4 + settings.speed) * dt
            }
            if f.position.x < -20 { f.position.x = size.width + 10 }
            if f.position.x > size.width + 20 { f.position.x = -10 }
            if settings.accumulation, let hit = landing(from: old, to: f.position, radius: f.radius) {
                deposit(on: hit, x: f.position.x, amount: f.radius * 0.75)
                if f.debris { f.life = -1 } else { f = freshFlake(initial: false) }
            } else if f.position.y > size.height + 15 {
                if f.debris { f.life = -1 } else { f = freshFlake(initial: false) }
            }
            flakes[i] = f
        }
        flakes.removeAll { $0.debris && $0.life <= 0 }
        if flakes.count > 1800 { flakes.removeFirst(flakes.count - 1800) }
        if settings.automaticPlough && time >= nextPlough && ploughs.isEmpty { startPloughsOnWindows(includeGround: true) }
        stepPloughs(dt)
    }

    private func landing(from old: CGPoint, to new: CGPoint, radius: Double) -> Int? {
        guard new.y >= old.y else { return nil }
        return surfaces.indices.filter { index in
            let surface = surfaces[index]
            let y = surface.height(at: new.x) - radius
            return surface.contains(new.x) && old.y <= y + 1 && new.y >= y
        }.min { surfaces[$0].height(at: new.x) < surfaces[$1].height(at: new.x) }
    }

    private func deposit(on index: Int, x: Double, amount: Double) {
        guard surfaces.indices.contains(index) else { return }
        let spacing = surfaces[index].spacing
        let center = Int((x - surfaces[index].rect.minX) / spacing)
        let cap = settings.maxDepth * (surfaces[index].id == Self.groundID ? 1.7 : 1)
        for offset in -3...3 {
            let cell = center + offset
            guard surfaces[index].depths.indices.contains(cell) else { continue }
            let weight = exp(-Double(offset * offset) / 4.5)
            let cellX = surfaces[index].rect.minX + Double(cell) * spacing
            let naturalCap = surfaces[index].capacity(at: cellX, maximum: cap)
            surfaces[index].depths[cell] = min(naturalCap, surfaces[index].depths[cell] + amount * weight * 0.4)
        }
    }

    private func scatter(_ surface: SnowSurface, dx: Double) {
        guard settings.accumulation else { return }
        for i in stride(from: 0, to: surface.depths.count, by: 3) where surface.depths[i] > 0.8 {
            let x = surface.rect.minX + Double(i) * surface.spacing
            guard surface.contains(x) else { continue }
            flakes.append(Flake(position: CGPoint(x: x, y: surface.y - surface.depths[i]),
                velocity: CGVector(dx: max(-300, min(300, dx)) + random.value(-45, 45), dy: random.value(-65, -10)),
                radius: random.value(1.4, 3.2), opacity: 0.9, phase: 0, debris: true, life: 3))
        }
    }

    public func clear() {
        for i in surfaces.indices { surfaces[i].depths = surfaces[i].depths.map { _ in 0 } }
        ploughs.removeAll()
        flakes.removeAll { $0.debris }
    }

    public func seedAccumulation(depth: Double) {
        for s in surfaces.indices {
            for i in surfaces[s].depths.indices {
                let x = surfaces[s].rect.minX + Double(i) * surfaces[s].spacing
                surfaces[s].depths[i] = surfaces[s].capacity(at: x, maximum: min(settings.maxDepth, depth))
            }
        }
    }

    @discardableResult public func startPlough(on surfaceID: Int = SnowSimulation.groundID) -> Bool {
        guard let surface = surfaces.first(where: { $0.id == surfaceID }) else { return false }
        let routes = surface.spans.filter { $0.upper - $0.lower >= 70 }
        guard !routes.isEmpty else { return false }
        ploughs.removeAll { $0.surfaceID == surfaceID }
        for span in routes {
            let scale = surfaceID == Self.groundID ? 1.0 : 0.72
            let route = Span(span.lower - surface.rect.minX, span.upper - surface.rect.minX)
            ploughs.append(Snowplough(id: nextPloughID, surfaceID: surfaceID,
                localX: route.lower - 45 * scale, route: route, scale: scale))
            nextPloughID += 1
        }
        nextPlough = time + 85
        return true
    }

    public func startPloughsOnWindows(includeGround: Bool = false) {
        let ids = surfaces.filter { includeGround || $0.id != Self.groundID }.map(\.id)
        for id in ids { startPlough(on: id) }
    }

    public func position(of plough: Snowplough) -> CGPoint? {
        guard let surface = surfaces.first(where: { $0.id == plough.surfaceID }) else { return nil }
        return CGPoint(x: surface.rect.minX + plough.localX, y: surface.y)
    }

    private func stepPloughs(_ dt: Double) {
        for p in ploughs.indices {
            guard let s = surfaces.firstIndex(where: { $0.id == ploughs[p].surfaceID }) else { continue }
            let oldBlade = ploughs[p].localX + 31 * ploughs[p].scale
            ploughs[p].localX += (ploughs[p].surfaceID == Self.groundID ? 84 : 100) * dt
            let blade = ploughs[p].localX + 31 * ploughs[p].scale
            let lower = min(oldBlade, blade) - 14 * ploughs[p].scale
            let upper = max(oldBlade, blade) + 14 * ploughs[p].scale
            for i in surfaces[s].depths.indices {
                let localX = Double(i) * surfaces[s].spacing
                if localX >= lower && localX <= upper && surfaces[s].contains(surfaces[s].rect.minX + localX) {
                    surfaces[s].depths[i] = 0
                }
            }
        }
        ploughs.removeAll { $0.localX > $0.route.upper + 50 * $0.scale }
    }

}
