import AppKit

// Renders the ProfilePilot app icon: a link (white dot) fanning out to three
// profile dots on an indigo squircle, the chosen profile ringed in white.
// Usage: swift icon/generate.swift <output.iconset dir>
// Then:  iconutil -c icns -o Resources/AppIcon.icns <output.iconset dir>

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// Everything is drawn in a 1024x1024 coordinate space and scaled per size.
func drawIcon(_ cg: CGContext) {
    let rect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = CGPath(roundedRect: rect, cornerWidth: 185, cornerHeight: 185, transform: nil)
    cg.saveGState()
    cg.addPath(squircle)
    cg.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [CGColor(red: 0.14, green: 0.12, blue: 0.38, alpha: 1),
                 CGColor(red: 0.36, green: 0.38, blue: 0.92, alpha: 1)] as CFArray,
        locations: [0, 1])!
    cg.drawLinearGradient(gradient,
                          start: CGPoint(x: 512, y: 100),
                          end: CGPoint(x: 512, y: 924),
                          options: [])

    let origin = CGPoint(x: 320, y: 512)
    let destinations = [CGPoint(x: 700, y: 716), CGPoint(x: 700, y: 512), CGPoint(x: 700, y: 308)]

    cg.setLineCap(.round)
    for (index, destination) in destinations.enumerated() {
        let selected = index == 1
        cg.setStrokeColor(CGColor(gray: 1, alpha: selected ? 1.0 : 0.45))
        cg.setLineWidth(selected ? 26 : 20)
        cg.move(to: origin)
        cg.addCurve(to: destination,
                    control1: CGPoint(x: 510, y: origin.y),
                    control2: CGPoint(x: 540, y: destination.y))
        cg.strokePath()
    }

    cg.setFillColor(CGColor(gray: 1, alpha: 1))
    cg.fillEllipse(in: CGRect(x: origin.x - 38, y: origin.y - 38, width: 76, height: 76))

    let profileColors = [CGColor(red: 0.18, green: 0.83, blue: 0.75, alpha: 1),  // teal
                         CGColor(red: 0.99, green: 0.44, blue: 0.52, alpha: 1),  // rose
                         CGColor(red: 0.96, green: 0.65, blue: 0.10, alpha: 1)]  // amber
    for (index, destination) in destinations.enumerated() {
        let radius: CGFloat = 66
        cg.setFillColor(profileColors[index])
        cg.fillEllipse(in: CGRect(x: destination.x - radius, y: destination.y - radius,
                                  width: radius * 2, height: radius * 2))
    }

    // Ring the selected (middle) profile.
    cg.setStrokeColor(CGColor(gray: 1, alpha: 1))
    cg.setLineWidth(14)
    cg.strokeEllipse(in: CGRect(x: 700 - 94, y: 512 - 94, width: 188, height: 188))
    cg.restoreGState()
}

func writePNG(size: Int, scale: Int) {
    let px = size * scale
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let cg = ctx.cgContext
    cg.clear(CGRect(x: 0, y: 0, width: CGFloat(px), height: CGFloat(px)))
    cg.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
    drawIcon(cg)
    cg.flush()
    NSGraphicsContext.restoreGraphicsState()
    let name = scale == 1 ? "icon_\(size)x\(size).png" : "icon_\(size)x\(size)@\(scale)x.png"
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    writePNG(size: size, scale: 1)
    writePNG(size: size, scale: 2)
}
print("Wrote iconset to \(outDir)")
