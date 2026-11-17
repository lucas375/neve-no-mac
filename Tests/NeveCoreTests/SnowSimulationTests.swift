import XCTest
import CoreGraphics
@testable import NeveCore

final class SnowSimulationTests: XCTestCase {
    func testInvalidSavedValuesStayWithinSupportedLimits() throws {
        let data = Data(#"{"density":1e100,"speed":-10,"wind":99,"maxDepth":-200}"#.utf8)
        let settings = try JSONDecoder().decode(SnowSettings.self, from: data)
        XCTAssertEqual(settings.density, 1.5)
        XCTAssertEqual(settings.speed, 0.1)
        XCTAssertEqual(settings.wind, 1.5)
        XCTAssertEqual(settings.maxDepth, 8)
    }

    func testVeryWideWindowsHaveBoundedStorageAndResizeKeepsSnow() {
        let sim = SnowSimulation(size: CGSize(width: 3840, height: 2160))
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: -1000, y: 200, width: 100_000, height: 500))])
        XCTAssertLessThanOrEqual(sim.surfaces.first { $0.id == 1 }!.depths.count, 2048)
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: -1000, y: 200, width: 1e100, height: 500))])
        XCTAssertLessThanOrEqual(sim.surfaces.first { $0.id == 1 }!.depths.count, 2048)
        sim.seedAccumulation(depth: 12)
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 0, y: 200, width: 600, height: 500))])
        let surface = sim.surfaces.first { $0.id == 1 }!
        XCTAssertEqual(surface.depths.count, 151)
        XCTAssertTrue(surface.depths.contains { $0 > 0 })
    }

    func testSnowCanFallOffTheScreenWithoutLeavingAPile() {
        var settings = SnowSettings(); settings.accumulation = false; settings.showSnowman = false
        let sim = SnowSimulation(size: CGSize(width: 400, height: 300), settings: settings)
        for _ in 0..<900 { sim.step(1.0 / 30) }
        XCTAssertFalse(sim.settings.accumulation)
        XCTAssertFalse(sim.settings.showSnowman)
        XCTAssertTrue(sim.surfaces.allSatisfy { $0.depths.allSatisfy { $0 == 0 } })
        XCTAssertTrue(sim.flakes.allSatisfy { $0.position.y <= 315 })
        XCTAssertGreaterThan(sim.flakes.count, 0)
    }
    func testCoveredWindowEdgesDoNotCatchSnow() {
        let back = WindowGeometry(id: 1, rect: CGRect(x: 0, y: 100, width: 300, height: 200))
        let front = WindowGeometry(id: 2, rect: CGRect(x: 80, y: 50, width: 80, height: 150))
        XCTAssertEqual(SnowGeometry.exposedTop(of: back, inFront: [front], width: 300), [Span(0, 80), Span(160, 300)])
        let covering = WindowGeometry(id: 3, rect: CGRect(x: -10, y: 20, width: 320, height: 250))
        XCTAssertTrue(SnowGeometry.exposedTop(of: back, inFront: [covering], width: 300).isEmpty)
    }

    func testCoordinatesOnDisplaysLeftAndAboveThePrimary() {
        let left = SnowGeometry.localRect(quartz: CGRect(x: -1000, y: 500, width: 300, height: 200),
            screen: CGRect(x: -1920, y: 0, width: 1920, height: 1080), primaryHeight: 1440)
        XCTAssertEqual(left.origin, CGPoint(x: 920, y: 140))
        let above = SnowGeometry.localRect(quartz: CGRect(x: 100, y: -500, width: 300, height: 200),
            screen: CGRect(x: 0, y: 1440, width: 1600, height: 900), primaryHeight: 1440)
        XCTAssertEqual(above.origin, CGPoint(x: 100, y: 400))
    }

    func testMovingAWindowCarriesItsSnowImmediately() {
        var settings = SnowSettings(); settings.accumulation = true
        let sim = SnowSimulation(size: CGSize(width: 500, height: 400), settings: settings)
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 50, y: 150, width: 300, height: 200))])
        sim.seedAccumulation(depth: 12)
        let original = sim.surfaces.first { $0.id == 1 }!.depths
        for frame in 1...35 {
            let rect = CGRect(x: 50 + Double(frame) * 3, y: 150 + Double(frame) * 0.5, width: 300, height: 200)
            sim.updateWindows([WindowGeometry(id: 1, rect: rect)], elapsed: 1.0 / 60)
            let moved = sim.surfaces.first { $0.id == 1 }!
            XCTAssertEqual(moved.rect, rect)
            for (a, b) in zip(moved.depths, original) { XCTAssertEqual(a, b, accuracy: 0.001) }
        }
        XCTAssertFalse(sim.flakes.contains { $0.debris })
        XCTAssertGreaterThanOrEqual(sim.geometryRevision, 36)
    }

    func testShakingAWindowReleasesSnowWithoutEmptyingTheWholePile() {
        let sim = SnowSimulation(size: CGSize(width: 500, height: 400))
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 50, y: 150, width: 300, height: 200))])
        sim.seedAccumulation(depth: 16)
        let original = sim.surfaces.first { $0.id == 1 }!.depths.max()!
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 70, y: 150, width: 300, height: 200))], elapsed: 1.0 / 60)
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 40, y: 150, width: 300, height: 200))], elapsed: 1.0 / 60)
        let depth = sim.surfaces.first { $0.id == 1 }!.depths.max()!
        XCTAssertGreaterThan(depth, 0)
        XCTAssertLessThan(depth, original * 0.5)
        XCTAssertTrue(sim.flakes.contains { $0.debris && $0.velocity.dx < 0 })
    }

    func testAccumulationIsBoundedOverLongSimulation() {
        var settings = SnowSettings(); settings.maxDepth = 10; settings.accumulation = true
        let sim = SnowSimulation(size: CGSize(width: 300, height: 200), settings: settings)
        sim.updateWindows([WindowGeometry(id: 8, rect: CGRect(x: 0, y: 90, width: 300, height: 110))])
        for _ in 0..<1800 { sim.step(1.0 / 30) }
        XCTAssertGreaterThan(sim.surfaces.first { $0.id == 8 }!.depths.max()!, 0)
        for surface in sim.surfaces {
            let cap = surface.id == SnowSimulation.groundID ? 17.0 : 10.0
            XCTAssertTrue(surface.depths.allSatisfy { $0 >= 0 && $0 <= cap })
        }
        XCTAssertLessThan(sim.flakes.count, 1801)
    }

    func testPloughClearsTheFloorAndLeavesWindowSnow() {
        var settings = SnowSettings(); settings.accumulation = true
        let sim = SnowSimulation(size: CGSize(width: 300, height: 200), settings: settings)
        sim.updateWindows([WindowGeometry(id: 9, rect: CGRect(x: 0, y: 80, width: 300, height: 100))])
        sim.seedAccumulation(depth: 12)
        let windowBefore = sim.surfaces.first { $0.id == 9 }!.depths.reduce(0, +)
        let groundBefore = sim.surfaces.first { $0.id == SnowSimulation.groundID }!.depths.reduce(0, +)
        sim.startPlough()
        for _ in 0..<180 { sim.step(1.0 / 30) }
        XCTAssertGreaterThanOrEqual(sim.surfaces.first { $0.id == 9 }!.depths.reduce(0, +), windowBefore)
        XCTAssertLessThan(sim.surfaces.first { $0.id == SnowSimulation.groundID }!.depths.reduce(0, +), groundBefore * 0.3)
    }

    func testTractorCleansOnlyItsTargetWindow() {
        var settings = SnowSettings(); settings.automaticPlough = false
        let sim = SnowSimulation(size: CGSize(width: 400, height: 400), settings: settings)
        sim.updateWindows([
            WindowGeometry(id: 12, rect: CGRect(x: 0, y: 80, width: 400, height: 80)),
            WindowGeometry(id: 13, rect: CGRect(x: 0, y: 200, width: 400, height: 100))
        ])
        sim.seedAccumulation(depth: 16)
        let target = sim.surfaces.first { $0.id == 12 }!.depths.reduce(0, +)
        let other = sim.surfaces.first { $0.id == 13 }!.depths.reduce(0, +)
        XCTAssertTrue(sim.startPlough(on: 12))
        for _ in 0..<180 { sim.step(1.0 / 30) }
        XCTAssertLessThan(sim.surfaces.first { $0.id == 12 }!.depths.reduce(0, +), target * 0.3)
        XCTAssertGreaterThanOrEqual(sim.surfaces.first { $0.id == 13 }!.depths.reduce(0, +), other)
        XCTAssertTrue(sim.ploughs.isEmpty)
    }

    func testTractorMovesWithItsWindowAndIsRemovedWhenTheWindowCloses() {
        let sim = SnowSimulation(size: CGSize(width: 700, height: 500))
        sim.updateWindows([WindowGeometry(id: 7, rect: CGRect(x: 50, y: 150, width: 400, height: 200))])
        sim.startPlough(on: 7); sim.step(0.05)
        let before = sim.position(of: sim.ploughs[0])!
        sim.updateWindows([WindowGeometry(id: 7, rect: CGRect(x: 180, y: 220, width: 400, height: 200))])
        let after = sim.position(of: sim.ploughs[0])!
        XCTAssertEqual(after.x - before.x, 130, accuracy: 0.001)
        XCTAssertEqual(after.y - before.y, 70, accuracy: 0.001)
        sim.updateWindows([])
        XCTAssertTrue(sim.ploughs.isEmpty)
    }

    func testTractorRoutesRespectOccludedWindowEdges() {
        let sim = SnowSimulation(size: CGSize(width: 420, height: 400))
        sim.updateWindows([
            WindowGeometry(id: 2, rect: CGRect(x: 150, y: 40, width: 120, height: 130)),
            WindowGeometry(id: 1, rect: CGRect(x: 0, y: 100, width: 420, height: 200))
        ])
        sim.startPlough(on: 1)
        XCTAssertEqual(sim.ploughs.count, 2)
        XCTAssertEqual(sim.ploughs.map(\.route), [Span(0, 150), Span(270, 420)])
    }

    func testSaturatedSnowKeepsAnUnevenProfileAndSoftEdges() {
        var settings = SnowSettings(); settings.maxDepth = 30; settings.density = 1.5; settings.automaticPlough = false
        let sim = SnowSimulation(size: CGSize(width: 420, height: 180), settings: settings)
        sim.updateWindows([WindowGeometry(id: 1, rect: CGRect(x: 0, y: 85, width: 420, height: 95))])
        for _ in 0..<3000 { sim.step(1.0 / 30) }
        let depths = sim.surfaces.first { $0.id == 1 }!.depths
        let interior = Array(depths.dropFirst(8).dropLast(8))
        XCTAssertGreaterThan(interior.max()! - interior.min()!, 6)
        XCTAssertLessThan(depths[0], interior.max()! * 0.3)
        XCTAssertTrue(depths.allSatisfy { $0 >= 0 && $0 <= 30 })
    }

    func testClearingRemovesAccumulationAndTractors() {
        let sim = SnowSimulation(size: CGSize(width: 300, height: 200))
        sim.seedAccumulation(depth: 10)
        sim.startPlough()
        sim.clear()
        XCTAssertTrue(sim.ploughs.isEmpty)
        XCTAssertFalse(sim.flakes.contains { $0.debris })
        XCTAssertTrue(sim.surfaces.allSatisfy { $0.depths.allSatisfy { $0 == 0 } })
    }

    func testOlderPreferencesKeepTheirValuesAndDefaultToDownwardSnow() throws {
        let legacy = Data(#"{"density":0.87,"speed":0.53,"wind":-0.76,"maxDepth":28.2,"accumulation":true,"showSnowman":false,"automaticPlough":true}"#.utf8)
        let settings = try JSONDecoder().decode(SnowSettings.self, from: legacy)
        XCTAssertEqual(settings.density, 0.87)
        XCTAssertEqual(settings.speed, 0.53)
        XCTAssertEqual(settings.wind, -0.76)
        XCTAssertEqual(settings.maxDepth, 28.2)
        XCTAssertFalse(settings.showSnowman)
        XCTAssertEqual(settings.windDirection, .vertical)
        XCTAssertEqual(settings.horizontalWind, 0)
        XCTAssertEqual(try JSONDecoder().decode(SnowSettings.self, from: JSONEncoder().encode(settings)), settings)
    }

    func testDownwardSnowIgnoresPreviousLateralWindAndCanSwitchModes() {
        var calm = SnowSettings(); calm.accumulation = false
        var windy = calm; windy.wind = -1.5
        let a = SnowSimulation(size: CGSize(width: 1000, height: 800), settings: calm, seed: 42)
        let b = SnowSimulation(size: CGSize(width: 1000, height: 800), settings: windy, seed: 42)
        a.step(0.05); b.step(0.05)
        for (before, after) in zip(a.flakes, b.flakes) {
            XCTAssertEqual(before.position, after.position)
        }
        b.settings.windDirection = .lateral
        let old = b.flakes
        b.step(0.05)
        let visible = zip(old, b.flakes).filter { $0.0.position.x > 100 && $0.0.position.y < 700 }
        XCTAssertGreaterThan(visible.count, 0)
        XCTAssertTrue(visible.allSatisfy { $0.1.position.x < $0.0.position.x - 3 })
        XCTAssertTrue(visible.allSatisfy { $0.1.position.y > $0.0.position.y })
    }
}
