import AppKit
import QuartzCore
import NeveCore
import NeveRendering

/// Exercises only project-owned, offscreen objects; never opens windows or reads user preferences.
enum MemoryCheck {
    static func run() -> Int32 {
        NSApplication.shared.setActivationPolicy(.prohibited)
        weak var releasedView: SnowSceneView?
        var samples: [Double] = []
        var idleLayerCount = 0
        autoreleasepool {
            var settings = SnowSettings()
            settings.density = 1.5
            settings.automaticPlough = false
            let model = SnowSimulation(size: CGSize(width: 3840, height: 2160), settings: settings)
            let view = SnowSceneView(simulation: model)
            releasedView = view
            for cycle in 0..<6 {
                autoreleasepool {
                    let windows = (0..<20).map { index in
                        WindowGeometry(id: cycle * 100 + index,
                            rect: CGRect(x: 30 + index * 100, y: 100 + index * 75, width: 720, height: 400))
                    }
                    model.updateWindows(windows)
                    model.seedAccumulation(depth: 24)
                    model.startPloughsOnWindows(includeGround: true)
                    view.presentFrame()
                    model.updateWindows([])
                    view.presentFrame()
                }
                for _ in 0..<180 {
                    autoreleasepool { model.step(1.0 / 30); view.presentFrame() }
                }
                autoreleasepool {
                    model.clear()
                    view.refreshAccumulation()
                    CATransaction.flush()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
                }
                idleLayerCount = layerCount(view.layer)
                samples.append(residentMiB())
                print(String(format: "cycle=%d rss_mib=%.2f idle_layers=%d flakes=%d", cycle + 1,
                    samples.last!, idleLayerCount, model.flakes.count))
            }
        }
        CATransaction.flush()
        let growth = (samples.last ?? 0) - (samples.dropFirst().first ?? 0)
        let released = releasedView == nil
        print(String(format: "warm_growth_mib=%.2f scene_released=%@", growth, released.description))
        // This is a reproducible regression check, not a promise about total desktop/GPU memory.
        return released && idleLayerCount <= 64 && growth < 16 ? 0 : 1
    }

    private static func layerCount(_ layer: CALayer?) -> Int {
        guard let layer else { return 0 }
        return 1 + (layer.sublayers ?? []).reduce(0) { $0 + layerCount($1) }
    }

    private static func residentMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
}
