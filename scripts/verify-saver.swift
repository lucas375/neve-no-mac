import AppKit
import ScreenSaver

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: verify-saver.swift module.saver preview.png\n", stderr)
    exit(1)
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let moduleURL = URL(fileURLWithPath: CommandLine.arguments[1])
guard let bundle = Bundle(url: moduleURL) else { fatalError("Bundle not found") }
try bundle.loadAndReturnError()
guard let type = bundle.principalClass as? ScreenSaverView.Type else { fatalError("Principal class is not ScreenSaverView") }
let size = CGSize(width: 1060, height: 660)
guard let saver = type.init(frame: CGRect(origin: .zero, size: size), isPreview: false) else { fatalError("Cannot initialize screen saver") }
let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
window.contentView = saver
saver.layoutSubtreeIfNeeded()
saver.startAnimation()
let end = Date().addingTimeInterval(2)
while Date() < end {
    saver.animateOneFrame()
    RunLoop.main.run(until: Date().addingTimeInterval(1.0 / 30))
}
saver.displayIfNeeded()
guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Cannot allocate preview") }
let context = graphics.cgContext
context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
saver.draw(saver.bounds)
for canvas in saver.subviews {
    // The transparent canvas clears its backing store; composite that store separately.
    guard let overlay = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot allocate canvas") }
    overlay.translateBy(x: 0, y: size.height); overlay.scaleBy(x: 1, y: -1)
    canvas.layer?.render(in: overlay)
    if let image = overlay.makeImage() {
        context.saveGState()
        context.translateBy(x: 0, y: size.height); context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: size))
        context.restoreGState()
    }
}
NSGraphicsContext.restoreGraphicsState()
saver.stopAnimation()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("Loaded \(NSStringFromClass(type)); rendered \(saver.subviews.count) animation canvas; frame interval \(saver.animationTimeInterval)")
