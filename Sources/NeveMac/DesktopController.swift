import AppKit
import Combine
import NeveCore
import NeveRendering

final class Preferences: ObservableObject {
    @Published var snow: SnowSettings {
        didSet { persist(); changed?() }
    }
    @Published var running = true { didSet { changed?() } }
    @Published var desktopOnly: Bool { didSet { persist(); changed?() } }
    var changed: (() -> Void)?
    private let defaults = UserDefaults.standard
    init() {
        snow = (defaults.data(forKey: "snow").flatMap { try? JSONDecoder().decode(SnowSettings.self, from: $0) }) ?? SnowSettings()
        desktopOnly = defaults.bool(forKey: "desktopOnly")
        if defaults.integer(forKey: "ornamentsVersion") < 1 {
            snow.accumulation = true; snow.showSnowman = true; snow.automaticPlough = true
            desktopOnly = false
            defaults.set(1, forKey: "ornamentsVersion"); persist()
        }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(snow) { defaults.set(data, forKey: "snow") }
        defaults.set(desktopOnly, forKey: "desktopOnly")
    }
}

final class SnowPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DesktopController {
    struct Display {
        var panel: SnowPanel
        var view: SnowSceneView
        var screen: NSScreen
    }
    let preferences: Preferences
    private(set) var displays: [Display] = []
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var lastWindowScan = 0.0
    private var fastTrackingUntil = 0.0
    private(set) var frontWindowID: Int?
    private var sleeping = false
    var stateChanged: (() -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
        preferences.changed = { [weak self] in self?.applyPreferences() }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in self?.rebuildDisplays() })
        let workspace = NSWorkspace.shared.notificationCenter
        for notification in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspace.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = true
                self?.displays.forEach { $0.view.setAnimationPaused(true); $0.panel.orderOut(nil) }
            })
        }
        for notification in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspace.addObserver(forName: notification, object: nil, queue: .main) { [weak self] _ in
                self?.sleeping = false; self?.lastWindowScan = 0; self?.applyPreferences()
            })
        }
        rebuildDisplays()
        timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 0.001
        RunLoop.main.add(timer!, forMode: .common)
    }

    deinit {
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        displays.forEach { $0.panel.close() }
    }

    private func rebuildDisplays() {
        displays.forEach { $0.panel.close() }; displays.removeAll()
        for screen in NSScreen.screens {
            // The overlay ends below the menu bar so its controls always remain reachable.
            let frame = CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width,
                               height: screen.visibleFrame.maxY - screen.frame.minY)
            let model = SnowSimulation(size: frame.size, settings: preferences.snow,
                seed: UInt64(abs(screen.frame.minX) + frame.width) + 2026)
            let view = SnowSceneView(simulation: model)
            let panel = SnowPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
            panel.hidesOnDeactivate = false; panel.ignoresMouseEvents = true
            panel.isReleasedWhenClosed = false; panel.acceptsMouseMovedEvents = false
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = view
            displays.append(Display(panel: panel, view: view, screen: screen))
        }
        lastWindowScan = 0
        applyPreferences()
    }

    private func applyPreferences() {
        for display in displays {
            display.view.simulation.settings = preferences.snow
            display.view.setAnimationPaused(!preferences.running || sleeping)
            display.panel.level = preferences.desktopOnly
                ? NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                : .floating
            if preferences.running && !sleeping { display.panel.orderFrontRegardless() }
            else { display.panel.orderOut(nil) }
        }
        lastWindowScan = 0
        stateChanged?()
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = min(0.05, now - lastTick); lastTick = now
        guard preferences.running && !sleeping else { return }
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        if NSEvent.pressedMouseButtons & 1 != 0 { fastTrackingUntil = now + 0.25 }
        let scanInterval = now < fastTrackingUntil ? 1.0 / 60 : (lowPower ? 0.1 : 1.0 / 30)
        if (preferences.snow.accumulation || preferences.snow.showSnowman) && now - lastWindowScan >= scanInterval * 0.9 {
            updateWindowGeometry(elapsed: lastWindowScan == 0 ? scanInterval : now - lastWindowScan)
            lastWindowScan = now
        }
        for display in displays {
            let view = display.view
            guard display.panel.isVisible else { continue }
            view.simulation.step(dt, quality: lowPower ? 0.5 : 1)
            view.renderQuality = lowPower ? 0.5 : 1
            view.presentFrame()
        }
    }

    private func updateWindowGeometry(elapsed: Double = 1.0 / 60) {
        let rows = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]) ?? []
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var frontID: Int?
        for display in displays {
            var windows: [WindowGeometry] = []
            for row in rows {
                guard let pid = row[kCGWindowOwnerPID as String] as? Int32, pid != ownPID,
                      let id = row[kCGWindowNumber as String] as? Int,
                      let layer = row[kCGWindowLayer as String] as? Int,
                      let bounds = row[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                      (row[kCGWindowAlpha as String] as? Double ?? 1) > 0.05 else { continue }
                let local = SnowGeometry.localRect(quartz: rect, screen: display.panel.frame, primaryHeight: primaryHeight)
                let isDock = pid == dockPID && layer > 0 && local.width > 100 && local.width < display.panel.frame.width * 0.95 &&
                    local.height < 180 && local.minY > display.panel.frame.height * 0.7
                guard (layer == 0 || isDock), local.width >= 90, local.height >= 28,
                      local.intersects(CGRect(origin: .zero, size: display.panel.frame.size)) else { continue }
                windows.append(WindowGeometry(id: id, rect: local))
                if frontID == nil && layer == 0 && local.minY >= 3 { frontID = id }
            }
            display.view.simulation.updateWindows(preferences.desktopOnly ? [] : windows, elapsed: elapsed)
            if !display.panel.isVisible && preferences.running { display.panel.orderFrontRegardless() }
        }
        frontWindowID = frontID
    }

    func plough() {
        updateWindowGeometry()
        displays.forEach { $0.view.simulation.startPloughsOnWindows(includeGround: true); $0.view.presentFrame() }
    }
    func ploughFrontWindow() {
        updateWindowGeometry()
        guard let id = frontWindowID else { return }
        displays.forEach { $0.view.simulation.startPlough(on: id); $0.view.presentFrame() }
    }
    func ploughFloor() { displays.forEach { $0.view.simulation.startPlough(); $0.view.presentFrame() } }
    func clear() { displays.forEach { $0.view.simulation.clear(); $0.view.refreshAccumulation() } }
    var surfaceCount: Int { displays.reduce(0) { $0 + max(0, $1.view.simulation.surfaces.count - 1) } }
}
