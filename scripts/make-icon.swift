import AppKit
import ImageIO

guard CommandLine.arguments.count == 2 else {
    fputs("Uso: swift scripts/make-icon.swift caminho/NeveMac.iconset\n", stderr)
    exit(1)
}

let destination = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha])!
}

// Original vector artwork. Drawing each size directly keeps the flake crisp at Spotlight scale.
func drawIcon(pixels: Int) -> CGImage {
    guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
        bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Não foi possível criar o ícone")
    }
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let tile = CGPath(roundedRect: CGRect(x: 96, y: 96, width: 832, height: 832),
        cornerWidth: 186, cornerHeight: 186, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: color(0, 0.02, 0.06, 0.30))
    context.addPath(tile)
    context.setFillColor(color(0.035, 0.065, 0.11))
    context.fillPath()
    context.restoreGState()
    context.saveGState()
    context.addPath(tile)
    context.clip()
    let navy = CGGradient(colorsSpace: colorSpace,
        colors: [color(0.035, 0.065, 0.11), color(0.085, 0.17, 0.26)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(navy, start: CGPoint(x: 512, y: 96), end: CGPoint(x: 512, y: 928), options: [])
    context.restoreGState()
    context.addPath(tile)
    context.setLineWidth(3)
    context.setStrokeColor(color(0.40, 0.76, 0.90, 0.24))
    context.strokePath()

    let flake = CGMutablePath()
    let center = CGPoint(x: 512, y: 512)
    for arm in 0..<6 {
        let angle = CGFloat(arm) * .pi / 3
        let u = CGVector(dx: cos(angle), dy: sin(angle))
        let v = CGVector(dx: -u.dy, dy: u.dx)
        func point(_ radial: CGFloat, _ side: CGFloat = 0) -> CGPoint {
            CGPoint(x: center.x + u.dx * radial + v.dx * side,
                y: center.y + u.dy * radial + v.dy * side)
        }
        flake.move(to: center)
        flake.addLine(to: point(250))
        for side: CGFloat in [-1, 1] {
            flake.move(to: point(148))
            flake.addLine(to: point(207, side * 59))
            if pixels >= 64 {
                flake.move(to: point(86))
                flake.addLine(to: point(126, side * 40))
            }
        }
    }
    let stroke = flake.copy(strokingWithWidth: 29, lineCap: .round, lineJoin: .round, miterLimit: 10)
    context.saveGState()
    context.setShadow(offset: .zero, blur: 22, color: color(0.18, 0.80, 1, 0.40))
    context.addPath(stroke)
    context.setFillColor(color(0.26, 0.84, 1))
    context.fillPath()
    context.restoreGState()
    context.addPath(stroke)
    context.clip()
    let ice = CGGradient(colorsSpace: colorSpace,
        colors: [color(0.22, 0.80, 1), color(0.76, 0.97, 1)] as CFArray,
        locations: [0, 1])!
    context.drawLinearGradient(ice, start: CGPoint(x: 512, y: 250), end: CGPoint(x: 512, y: 774), options: [])
    return context.makeImage()!
}

let sizes = [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64),
    ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512),
    ("512x512", 512), ("512x512@2x", 1024)]
for (name, pixels) in sizes {
    let path = destination.appendingPathComponent("icon_\(name).png")
    guard let imageDestination = CGImageDestinationCreateWithURL(path as CFURL, "public.png" as CFString, 1, nil) else {
        fatalError("Não foi possível gravar \(path.lastPathComponent)")
    }
    CGImageDestinationAddImage(imageDestination, drawIcon(pixels: pixels), nil)
    guard CGImageDestinationFinalize(imageDestination) else { fatalError("Falha ao gravar o ícone") }
}
print("Ícone de floco de neve gerado: \(destination.path)")
