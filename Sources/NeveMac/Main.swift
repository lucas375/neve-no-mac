import AppKit
import SwiftUI
import NeveCore
import NeveRendering

final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences()
    var desktop: DesktopController?
    var statusItem: NSStatusItem?
    let settingsPopover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "Ajustes…", action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self; appMenu.addItem(settingsItem); appMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Sair do Neve no Mac", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self; appMenu.addItem(quitItem)
        appItem.submenu = appMenu; mainMenu.addItem(appItem); NSApplication.shared.mainMenu = mainMenu
        desktop = DesktopController(preferences: preferences)
        desktop?.stateChanged = { [weak self] in self?.refreshMenu() }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Neve no Mac")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "Neve no Mac · Clique para ajustar"
        item.button?.setAccessibilityLabel("Ajustes de Neve no Mac")
        item.button?.target = self; item.button?.action = #selector(togglePopover)
        statusItem = item
        settingsPopover.behavior = .transient
        settingsPopover.appearance = NSAppearance(named: .darkAqua)
        let content = SettingsView(preferences: preferences,
            plough: { [weak self] in self?.desktop?.plough() },
            frontPlough: { [weak self] in self?.desktop?.ploughFrontWindow() },
            floorPlough: { [weak self] in self?.desktop?.ploughFloor() },
            clear: { [weak self] in self?.clearSnow() },
            close: { [weak self] in self?.settingsPopover.performClose(nil) },
            quit: { [weak self] in self?.quit() })
        let host = NSHostingController(rootView: content)
        settingsPopover.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        settingsPopover.contentSize = host.view.fittingSize
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func refreshMenu() {
        statusItem?.button?.appearsDisabled = !preferences.running
    }
    @objc func toggleSnow() { preferences.running.toggle() }
    @objc func sendPlough() { desktop?.plough() }
    @objc func clearSnow() { desktop?.clear() }
    @objc func quit() { NSApplication.shared.terminate(nil) }
    @objc func togglePopover() {
        if settingsPopover.isShown { settingsPopover.performClose(nil) }
        else { showSettings() }
    }
    @objc func showSettings() {
        guard let button = statusItem?.button else { return }
        NSApplication.shared.activate(ignoringOtherApps: true)
        settingsPopover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        settingsPopover.contentViewController?.view.window?.makeKey()
    }
}

@main enum NeveMacMain {
    static func main() {
        let app = NSApplication.shared
        if CommandLine.arguments.contains("--memory-check") { exit(MemoryCheck.run()) }
        if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
            let path = CommandLine.arguments[index + 1]
            let size = CGSize(width: 1060, height: 360)
            let model = makePreview(size: size, settings: SnowSettings())
            for _ in 0..<90 { model.step(1.0 / 30) }
            let view = SnowSceneView(simulation: model, preview: true, staticRendering: true)
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { exit(1) }
            NSGraphicsContext.saveGraphicsState()
            let ctx = graphics.cgContext
            ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
            if CommandLine.arguments.contains("--check-sprites") {
                let gpu = SnowSceneView(simulation: model, preview: true)
                gpu.presentFrame()
                print(gpu.renderSpriteDiagnostics(in: ctx))
            } else { view.draw(view.bounds) }
            NSGraphicsContext.restoreGraphicsState()
            do {
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
                print("Prévia salva: \(path)")
            } catch { fputs("Falha ao salvar prévia: \(error)\n", stderr); exit(1) }
            return
        }
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate(); app.delegate = delegate
        app.run()
        withExtendedLifetime(delegate) {}
    }
}
