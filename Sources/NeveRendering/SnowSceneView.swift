import AppKit
import QuartzCore
import NeveCore

public final class SnowSceneView: NSView {
    public var simulation: SnowSimulation
    public var isPreview = false
    public var renderQuality = 1.0
    private let staticRendering: Bool
    private let snowfall = CAEmitterLayer()
    private let sprites = CALayer()
    private let drifts = CALayer()
    private var surfaceLayers: [Int: CAShapeLayer] = [:]
    private var ploughLayers: [Int: CALayer] = [:]
    private var debrisLayers: [CALayer] = []
    private let snowmanLayer = CALayer()
    private var ploughTexture: CGImage?
    private var flakeTexture: CGImage?
    private var configuredSettings: SnowSettings?
    private var configuredSize = CGSize.zero
    private var lastPaint = -1.0
    private var configuredQuality = 1.0
    private var paintedGeometryRevision = -1
    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { false }
    public override var acceptsFirstResponder: Bool { false }

    public init(simulation: SnowSimulation, preview: Bool = false, staticRendering: Bool = false) {
        self.simulation = simulation; self.isPreview = preview; self.staticRendering = staticRendering
        super.init(frame: CGRect(origin: .zero, size: simulation.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(false)
        if !staticRendering {
            // Core Animation uses y-up coordinates even though this NSView draws flipped.
            snowfall.isGeometryFlipped = false; sprites.isGeometryFlipped = false; drifts.isGeometryFlipped = false
            snowfall.masksToBounds = true; sprites.masksToBounds = true; drifts.masksToBounds = true
            drifts.zPosition = 0.5; snowfall.zPosition = 1; sprites.zPosition = 2
            layer?.addSublayer(drifts); layer?.addSublayer(snowfall); layer?.addSublayer(sprites)
            sprites.addSublayer(snowmanLayer)
            flakeTexture = texture(size: CGSize(width: 16, height: 16)) { ctx in
                let colors = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.8).cgColor, NSColor.white.withAlphaComponent(0).cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                    ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: 8, y: 8), startRadius: 0,
                                           endCenter: CGPoint(x: 8, y: 8), endRadius: 8, options: [])
                }
            }
            ploughTexture = texture(size: CGSize(width: 90, height: 52)) { ctx in self.drawPlough(x: 30, baseline: 48, in: ctx) }
            snowmanLayer.contents = texture(size: CGSize(width: 56, height: 88)) { ctx in self.drawSnowman(at: CGPoint(x: 28, y: 84), in: ctx) }
            snowmanLayer.bounds = CGRect(x: 0, y: 0, width: 56, height: 88)
            presentFrame()
        }
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configuredSize = .zero
        presentFrame()
    }

    private func layerPoint(_ point: CGPoint, in target: CALayer) -> CGPoint {
        // AppKit owns the backing layer's orientation; do not infer it from isFlipped.
        target.convert(convertToLayer(point), from: layer)
    }

    public func renderSpriteDiagnostics(in context: CGContext) -> String {
        layer?.render(in: context)
        return "ploughs=\(ploughLayers.count), texture=\(ploughTexture != nil), piles=\(surfaceLayers.count)"
    }

    private func texture(size: CGSize, drawing: (CGContext) -> Void) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: 2, y: 2); ctx.translateBy(x: 0, y: size.height); ctx.scaleBy(x: 1, y: -1)
        drawing(ctx); return ctx.makeImage()
    }

    public func setAnimationPaused(_ paused: Bool) {
        guard !staticRendering else { return }
        if paused && snowfall.speed != 0 {
            let time = snowfall.convertTime(CACurrentMediaTime(), from: nil)
            snowfall.speed = 0; snowfall.timeOffset = time
        } else if !paused && snowfall.speed == 0 {
            let time = snowfall.timeOffset
            snowfall.speed = 1; snowfall.timeOffset = 0; snowfall.beginTime = 0
            snowfall.beginTime = snowfall.convertTime(CACurrentMediaTime(), from: nil) - time
        }
    }

    public func refreshAccumulation() { lastPaint = -100; presentFrame() }

    public func presentFrame() {
        guard !staticRendering else { needsDisplay = true; return }
        let settings = simulation.settings
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if configuredSize != bounds.size || configuredSettings?.density != settings.density ||
            configuredSettings?.speed != settings.speed || configuredSettings?.wind != settings.wind ||
            configuredSettings?.windDirection != settings.windDirection || configuredQuality != renderQuality {
            snowfall.frame = bounds; sprites.frame = bounds; drifts.frame = bounds
            snowfall.emitterPosition = layerPoint(CGPoint(x: bounds.midX, y: -6), in: snowfall)
            snowfall.emitterSize = CGSize(width: bounds.width + 100, height: 1)
            snowfall.emitterShape = .line; snowfall.emitterMode = .surface
            snowfall.renderMode = .unordered; snowfall.seed = 2026
            let count = min(1300, max(30, bounds.width * bounds.height / 2400 * settings.density * renderQuality))
            let top = layerPoint(CGPoint(x: 0, y: 0), in: snowfall)
            let bottom = layerPoint(CGPoint(x: 0, y: bounds.height), in: snowfall)
            let down = bottom.y > top.y ? 1.0 : -1.0
            snowfall.emitterCells = [0.65, 1.0, 1.45].enumerated().map { index, depth in
                let cell = CAEmitterCell()
                let vertical = (35 + depth * 20) * (0.4 + settings.speed)
                let horizontal = settings.horizontalWind * 65
                let lifetime = bounds.height / vertical + 3
                cell.contents = flakeTexture
                cell.birthRate = Float(count * [0.48, 0.34, 0.18][index] / lifetime)
                cell.lifetime = Float(lifetime); cell.lifetimeRange = 2
                cell.velocity = hypot(vertical, horizontal); cell.velocityRange = vertical * 0.15
                cell.emissionLongitude = atan2(down * vertical, horizontal)
                cell.emissionRange = settings.windDirection == .vertical ? 0.07 : 0.16
                cell.yAcceleration = down * 1.5
                cell.scale = depth * 0.13; cell.scaleRange = 0.035
                cell.alphaRange = 0.2; cell.color = NSColor.white.withAlphaComponent(0.45 + depth * 0.3).cgColor
                return cell
            }
            configuredSize = bounds.size
            configuredQuality = renderQuality
        }
        let debris = simulation.flakes.filter { $0.debris }
        while debrisLayers.count < debris.count {
            let sprite = CALayer(); sprite.contents = flakeTexture; sprites.addSublayer(sprite); debrisLayers.append(sprite)
        }
        // Keep a small reusable pool; release a burst's unused layers once its flakes disappear.
        let retainedCount = max(debris.count, 32)
        while debrisLayers.count > retainedCount { debrisLayers.removeLast().removeFromSuperlayer() }
        for (index, sprite) in debrisLayers.enumerated() {
            sprite.isHidden = index >= debris.count
            if index < debris.count {
                let f = debris[index]
                sprite.position = layerPoint(f.position, in: sprites)
                sprite.bounds = CGRect(x: 0, y: 0, width: f.radius * 2, height: f.radius * 2)
                sprite.opacity = Float(f.opacity)
            }
        }
        let changed = configuredSettings != settings
        let geometryChanged = paintedGeometryRevision != simulation.geometryRevision
        drifts.isHidden = !settings.accumulation
        if changed || geometryChanged || simulation.time - lastPaint >= 0.08 {
            for id in Array(surfaceLayers.keys) where !simulation.surfaces.contains(where: { $0.id == id }) {
                surfaceLayers.removeValue(forKey: id)?.removeFromSuperlayer()
            }
            if settings.accumulation {
                for surface in simulation.surfaces {
                    let shape: CAShapeLayer
                    if let existing = surfaceLayers[surface.id] { shape = existing }
                    else {
                        shape = CAShapeLayer()
                        shape.fillColor = NSColor(calibratedRed: 0.92, green: 0.96, blue: 1, alpha: 0.98).cgColor
                        shape.strokeColor = NSColor.white.withAlphaComponent(0.9).cgColor
                        shape.lineWidth = 0.65
                        shape.lineJoin = .round
                        surfaceLayers[surface.id] = shape; drifts.addSublayer(shape)
                    }
                    shape.frame = bounds
                    shape.path = outline(surface) { self.layerPoint($0, in: shape) }
                }
            }
            lastPaint = simulation.time; paintedGeometryRevision = simulation.geometryRevision
            if isPreview && geometryChanged { needsDisplay = true }
        }
        snowmanLayer.isHidden = !settings.showSnowman
        let anchor = snowmanAnchor()
        snowmanLayer.position = layerPoint(CGPoint(x: anchor.x, y: anchor.y - 40), in: sprites)
        for id in Array(ploughLayers.keys) where !simulation.ploughs.contains(where: { $0.id == id }) {
            ploughLayers.removeValue(forKey: id)?.removeFromSuperlayer()
        }
        for plough in simulation.ploughs {
            guard let pose = simulation.position(of: plough),
                  let surface = simulation.surfaces.first(where: { $0.id == plough.surfaceID }) else { continue }
            let sprite: CALayer
            if let existing = ploughLayers[plough.id] { sprite = existing }
            else {
                sprite = CALayer(); sprite.contents = ploughTexture
                sprite.mask = CAShapeLayer()
                ploughLayers[plough.id] = sprite; sprites.addSublayer(sprite)
            }
            sprite.bounds = CGRect(x: 0, y: 0, width: 90 * plough.scale, height: 52 * plough.scale)
            sprite.position = layerPoint(CGPoint(x: pose.x + 15 * plough.scale, y: pose.y - 22 * plough.scale), in: sprites)
            if let mask = sprite.mask as? CAShapeLayer {
                mask.frame = sprite.bounds
                let path = CGMutablePath()
                for span in surface.spans {
                    let a = layerPoint(CGPoint(x: span.lower, y: surface.y - 55 * plough.scale), in: sprite)
                    let b = layerPoint(CGPoint(x: span.upper, y: surface.y + 5), in: sprite)
                    path.addRect(CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y)))
                }
                mask.path = path
            }
        }
        CATransaction.commit()
        if changed { needsDisplay = true }
        configuredSettings = settings
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        if isPreview { drawPreview(in: ctx) }
        if staticRendering && simulation.settings.accumulation {
            for surface in simulation.surfaces { drawPile(surface, in: ctx) }
        }
        for flake in simulation.flakes where staticRendering {
            ctx.setFillColor(NSColor(white: 1, alpha: flake.opacity).cgColor)
            let r = flake.radius
            ctx.fillEllipse(in: CGRect(x: flake.position.x - r, y: flake.position.y - r, width: r * 2, height: r * 2))
        }
        if staticRendering && simulation.settings.showSnowman { drawSnowman(at: snowmanAnchor(), in: ctx) }
        if staticRendering {
            for plough in simulation.ploughs {
                guard let position = simulation.position(of: plough),
                      let surface = simulation.surfaces.first(where: { $0.id == plough.surfaceID }) else { continue }
                ctx.saveGState()
                for span in surface.spans { ctx.addRect(CGRect(x: span.lower, y: surface.y - 60, width: span.upper - span.lower, height: 65)) }
                ctx.clip(); ctx.translateBy(x: position.x, y: position.y); ctx.scaleBy(x: plough.scale, y: plough.scale)
                drawPlough(x: 0, baseline: 0, in: ctx)
                ctx.restoreGState()
            }
        }
        ctx.restoreGState()
    }

    private func outline(_ surface: SnowSurface, map: (CGPoint) -> CGPoint = { $0 }) -> CGPath {
        let path = CGMutablePath()
        guard surface.depths.contains(where: { $0 > 0.15 }) else { return path }
        for span in surface.spans {
            var points = [CGPoint(x: span.lower, y: surface.height(at: span.lower))]
            for i in surface.depths.indices {
                let x = surface.rect.minX + Double(i) * surface.spacing
                if x > span.lower && x < span.upper { points.append(CGPoint(x: x, y: surface.y - surface.depths[i])) }
            }
            points.append(CGPoint(x: span.upper, y: surface.height(at: span.upper)))
            path.move(to: map(CGPoint(x: span.lower, y: surface.y + 0.6)))
            path.addLine(to: map(points[0]))
            for i in 0..<(points.count - 1) {
                let p0 = points[max(0, i - 1)], p1 = points[i], p2 = points[i + 1], p3 = points[min(points.count - 1, i + 2)]
                let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
                let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
                path.addCurve(to: map(p2), control1: map(c1), control2: map(c2))
            }
            path.addLine(to: map(CGPoint(x: span.upper, y: surface.y + 0.6))); path.closeSubpath()
        }
        return path
    }

    private func drawPile(_ surface: SnowSurface, in ctx: CGContext) {
        guard surface.depths.contains(where: { $0 > 0.15 }) else { return }
        ctx.saveGState()
        for span in surface.spans {
            ctx.addRect(CGRect(x: span.lower, y: surface.y - 100, width: span.upper - span.lower, height: 103))
        }
        ctx.clip()
        let path = outline(surface)
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 2, color: NSColor.black.withAlphaComponent(0.12).cgColor)
        ctx.setFillColor(NSColor(calibratedRed: 0.92, green: 0.96, blue: 1, alpha: 0.97).cgColor)
        ctx.addPath(path); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.1)
        ctx.addPath(path)
        ctx.strokePath(); ctx.restoreGState()
    }

    private func drawSnowSphere(at p: CGPoint, radius r: Double, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 1, height: 2), blur: 3, color: NSColor.black.withAlphaComponent(0.16).cgColor)
        ctx.setFillColor(NSColor(calibratedRed: 0.81, green: 0.9, blue: 0.99, alpha: 1).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        ctx.setShadow(offset: .zero, blur: 0)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.92).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.83, y: p.y - r * 0.88, width: r * 1.65, height: r * 1.65))
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.6).cgColor)
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.5, y: p.y - r * 0.65, width: r * 0.5, height: r * 0.3))
        ctx.restoreGState()
    }

    private func snowmanAnchor() -> CGPoint {
        let anchor = simulation.surfaces.first { surface in
            surface.id != SnowSimulation.groundID && surface.spans.contains {
                $0.upper - $0.lower > 120 && surface.height(at: $0.lower + ($0.upper - $0.lower) * 0.73) > 84
            }
        }
        let span = anchor?.spans.first(where: { $0.upper - $0.lower > 120 })
        let x = span.map { $0.lower + ($0.upper - $0.lower) * 0.73 } ?? (bounds.width * 0.82)
        let y = anchor?.height(at: x) ?? (bounds.height - 3)
        return CGPoint(x: x, y: y)
    }

    private func drawSnowman(at anchor: CGPoint, in ctx: CGContext) {
        let x = anchor.x, y = anchor.y
        drawSnowSphere(at: CGPoint(x: x, y: y - 16), radius: 17, in: ctx)
        drawSnowSphere(at: CGPoint(x: x, y: y - 40), radius: 13, in: ctx)
        drawSnowSphere(at: CGPoint(x: x, y: y - 60), radius: 10, in: ctx)
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.19, blue: 0.28, alpha: 1).cgColor)
        for p in [CGPoint(x: x - 3, y: y - 62), CGPoint(x: x + 4, y: y - 62), CGPoint(x: x, y: y - 40), CGPoint(x: x, y: y - 33)] {
            ctx.fillEllipse(in: CGRect(x: p.x - 1, y: p.y - 1, width: 2.4, height: 2.4))
        }
        ctx.setFillColor(NSColor.systemOrange.cgColor)
        ctx.move(to: CGPoint(x: x, y: y - 59)); ctx.addLine(to: CGPoint(x: x + 12, y: y - 57)); ctx.addLine(to: CGPoint(x: x, y: y - 55)); ctx.closePath(); ctx.fillPath()
        ctx.setFillColor(NSColor(calibratedRed: 0.88, green: 0.18, blue: 0.24, alpha: 1).cgColor)
        ctx.fill(CGRect(x: x - 11, y: y - 52, width: 22, height: 5))
        ctx.fill(CGRect(x: x + 4, y: y - 49, width: 5, height: 15))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x - 10, y: y - 75, width: 20, height: 9), cornerWidth: 4, cornerHeight: 4, transform: nil)); ctx.fillPath()
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: x - 12, y: y - 69, width: 24, height: 4))
        ctx.fillEllipse(in: CGRect(x: x + 5, y: y - 80, width: 7, height: 7))
    }

    private func drawPlough(x: Double, baseline: Double? = nil, in ctx: CGContext) {
        let y = baseline ?? (bounds.height - 4)
        ctx.saveGState(); ctx.translateBy(x: x, y: y)
        ctx.setFillColor(NSColor(calibratedRed: 0.12, green: 0.2, blue: 0.3, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -25, y: -12, width: 53, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)); ctx.fillPath()
        for wheel in stride(from: -18.0, through: 20, by: 9.5) {
            ctx.setFillColor(NSColor(calibratedRed: 0.64, green: 0.73, blue: 0.84, alpha: 1).cgColor)
            ctx.fillEllipse(in: CGRect(x: wheel - 3.5, y: -9, width: 7, height: 7))
            ctx.setFillColor(NSColor.darkGray.cgColor); ctx.fillEllipse(in: CGRect(x: wheel - 1.3, y: -6.8, width: 2.6, height: 2.6))
        }
        ctx.setFillColor(NSColor(calibratedRed: 1, green: 0.76, blue: 0.19, alpha: 1).cgColor)
        ctx.addPath(CGPath(roundedRect: CGRect(x: -25, y: -22, width: 49, height: 13), cornerWidth: 3, cornerHeight: 3, transform: nil)); ctx.fillPath()
        ctx.fill(CGRect(x: -14, y: -37, width: 23, height: 19))
        ctx.setFillColor(NSColor(calibratedRed: 0.58, green: 0.83, blue: 0.95, alpha: 1).cgColor)
        ctx.fill(CGRect(x: -10, y: -33, width: 15, height: 12))
        ctx.setFillColor(NSColor.white.cgColor); ctx.fill(CGRect(x: -17, y: -39, width: 29, height: 3))
        ctx.setFillColor(NSColor.systemOrange.withAlphaComponent(0.65 + 0.35 * sin(simulation.time * 10)).cgColor)
        ctx.fillEllipse(in: CGRect(x: -5, y: -44, width: 6, height: 5))
        ctx.setFillColor(NSColor(calibratedRed: 0.7, green: 0.84, blue: 0.94, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: 25, y: -16)); ctx.addLine(to: CGPoint(x: 39, y: -27)); ctx.addLine(to: CGPoint(x: 39, y: -2)); ctx.addLine(to: CGPoint(x: 25, y: -7)); ctx.closePath(); ctx.fillPath()
        ctx.restoreGState()
    }

    private func drawPreview(in ctx: CGContext) {
        ctx.setFillColor(NSColor(calibratedRed: 0.04, green: 0.09, blue: 0.19, alpha: 1).cgColor); ctx.fill(bounds)
        ctx.setFillColor(NSColor(calibratedRed: 0.1, green: 0.19, blue: 0.33, alpha: 1).cgColor)
        ctx.move(to: CGPoint(x: 0, y: bounds.height))
        for i in 0...8 { ctx.addLine(to: CGPoint(x: Double(i) * bounds.width / 8, y: bounds.height * (i.isMultiple(of: 2) ? 0.42 : 0.8))) }
        ctx.addLine(to: CGPoint(x: bounds.width, y: bounds.height)); ctx.closePath(); ctx.fillPath()
        for surface in simulation.surfaces where surface.id != SnowSimulation.groundID {
            let rect = surface.rect
            ctx.setFillColor(NSColor(calibratedRed: 0.14, green: 0.21, blue: 0.32, alpha: 1).cgColor)
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 8, cornerHeight: 8, transform: nil)); ctx.fillPath()
            for (i, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                ctx.setFillColor(color.withAlphaComponent(0.9).cgColor)
                ctx.fillEllipse(in: CGRect(x: rect.minX + 12 + Double(i) * 12, y: rect.minY + 12, width: 6, height: 6))
            }
            ctx.setFillColor(NSColor.white.withAlphaComponent(0.1).cgColor)
            for i in 0..<3 { ctx.fill(CGRect(x: rect.minX + 14, y: rect.minY + 40 + Double(i) * 13, width: rect.width * (i == 1 ? 0.5 : 0.72), height: 3)) }
        }
    }

}
