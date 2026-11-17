import AppKit
import ScreenSaver
import NeveCore
import NeveRendering

@objc(NeveScreenSaverView)
public final class NeveScreenSaverView: ScreenSaverView {
    private var canvas: SnowSceneView?
    private var background: NSImage?
    private var lastFrame = 0.0
    private var previewMode = false

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { true }

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        previewMode = isPreview
        prepare()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        prepare()
    }

    private func prepare() {
        wantsLayer = true
        animationTimeInterval = 1.0 / 30
        if let url = Bundle(for: Self.self).url(forResource: "Background", withExtension: "image") {
            background = NSImage(contentsOf: url)
        }
        rebuildScene()
    }

    private func rebuildScene() {
        guard bounds.width > 0 && bounds.height > 0 else { return }
        let resources = Bundle(for: Self.self)
        let defaults = ScreenSaverDefaults(forModuleWithName: "local.lucas.nevemac.screensaver")
        let saved = defaults?.data(forKey: "snow")
            ?? resources.url(forResource: "SnowSettings", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
        var settings = saved.flatMap { try? JSONDecoder().decode(SnowSettings.self, from: $0) } ?? SnowSettings()
        settings.accumulation = true
        settings.showSnowman = true
        settings.automaticPlough = true
        let model = SnowSimulation(size: bounds.size, settings: settings, seed: 4831)
        model.seedAccumulation(depth: min(12, settings.maxDepth))
        model.startPlough()
        canvas?.removeFromSuperview()
        let view = SnowSceneView(simulation: model)
        view.frame = bounds
        view.autoresizingMask = [.width, .height]
        addSubview(view)
        canvas = view
        needsDisplay = true
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if canvas != nil && canvas?.simulation.size != newSize { rebuildScene() }
    }

    public override func startAnimation() {
        super.startAnimation()
        lastFrame = ProcessInfo.processInfo.systemUptime
        canvas?.setAnimationPaused(false)
    }

    public override func stopAnimation() {
        canvas?.setAnimationPaused(true)
        super.stopAnimation()
    }

    public override func animateOneFrame() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastFrame > 0 ? min(0.05, now - lastFrame) : animationTimeInterval
        lastFrame = now
        canvas?.simulation.step(max(0, dt), quality: previewMode ? 0.7 : 1)
        canvas?.renderQuality = previewMode ? 0.7 : 1
        canvas?.presentFrame()
    }

    public override func draw(_ rect: NSRect) {
        NSColor(calibratedRed: 0.035, green: 0.07, blue: 0.14, alpha: 1).setFill()
        bounds.fill()
        if let image = background, image.size.width > 0 && image.size.height > 0 {
            let factor = max(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * factor, height: image.size.height * factor)
            let frame = CGRect(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2, width: size.width, height: size.height)
            image.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }
}
