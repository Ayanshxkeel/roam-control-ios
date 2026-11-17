import AppKit
import CoreGraphics
import ImageIO

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: size * 4, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}
let gradient = CGGradient(colorsSpace: space, colors: [color(0.025, 0.06, 0.13), color(0.04, 0.26, 0.30)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 1024, y: 1024), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.setLineWidth(4)
ctx.setStrokeColor(color(0.23, 0.72, 0.74, 0.19))
for offset in stride(from: -800, through: 1300, by: 105) {
    ctx.move(to: CGPoint(x: offset, y: 0))
    ctx.addLine(to: CGPoint(x: offset + 600, y: 1024))
    ctx.move(to: CGPoint(x: 0, y: offset + 300))
    ctx.addLine(to: CGPoint(x: 1024, y: offset - 200))
}
ctx.strokePath()
ctx.setLineCap(.round)
ctx.setLineWidth(25)
ctx.setStrokeColor(color(0.28, 0.95, 0.78))
ctx.move(to: CGPoint(x: 235, y: 298))
ctx.addCurve(to: CGPoint(x: 775, y: 302), control1: CGPoint(x: 394, y: 145), control2: CGPoint(x: 598, y: 149))
ctx.strokePath()
for p in [CGPoint(x: 235, y: 298), CGPoint(x: 775, y: 302)] {
    ctx.setFillColor(color(0.84, 1, 0.95))
    ctx.fillEllipse(in: CGRect(x: p.x - 20, y: p.y - 20, width: 40, height: 40))
}
let pin = CGMutablePath()
pin.move(to: CGPoint(x: 512, y: 264))
pin.addCurve(to: CGPoint(x: 291, y: 602), control1: CGPoint(x: 449, y: 345), control2: CGPoint(x: 291, y: 488))
pin.addArc(center: CGPoint(x: 512, y: 602), radius: 221, startAngle: .pi, endAngle: 0, clockwise: true)
pin.addCurve(to: CGPoint(x: 512, y: 264), control1: CGPoint(x: 733, y: 488), control2: CGPoint(x: 575, y: 345))
pin.closeSubpath()
ctx.setFillColor(color(0.30, 0.96, 0.79))
ctx.addPath(pin)
ctx.fillPath()
ctx.setFillColor(color(0.04, 0.15, 0.22))
ctx.move(to: CGPoint(x: 625, y: 687))
ctx.addLine(to: CGPoint(x: 523, y: 498))
ctx.addLine(to: CGPoint(x: 492, y: 574))
ctx.addLine(to: CGPoint(x: 418, y: 605))
ctx.closePath()
ctx.fillPath()
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let output = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(output, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(output))
