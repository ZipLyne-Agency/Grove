import AppKit
let output = CommandLine.arguments[1]
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let square = NSBezierPath(roundedRect: NSRect(x: 40, y: 40, width: 944, height: 944), xRadius: 220, yRadius: 220)
NSGradient(starting: NSColor(red: 0.31, green: 0.71, blue: 0.55, alpha: 1), ending: NSColor(red: 0.09, green: 0.30, blue: 0.23, alpha: 1))!.draw(in: square, angle: -70)
let leaf = NSBezierPath()
leaf.move(to: NSPoint(x: 322, y: 335))
leaf.curve(to: NSPoint(x: 719, y: 750), controlPoint1: NSPoint(x: 194, y: 684), controlPoint2: NSPoint(x: 536, y: 783))
leaf.curve(to: NSPoint(x: 322, y: 335), controlPoint1: NSPoint(x: 790, y: 416), controlPoint2: NSPoint(x: 546, y: 259))
NSColor.white.withAlphaComponent(0.96).setFill(); leaf.fill()
let stem = NSBezierPath()
stem.move(to: NSPoint(x: 285, y: 259))
stem.curve(to: NSPoint(x: 603, y: 625), controlPoint1: NSPoint(x: 358, y: 377), controlPoint2: NSPoint(x: 486, y: 530))
stem.lineWidth = 28; stem.lineCapStyle = .round
NSColor(red: 0.16, green: 0.43, blue: 0.32, alpha: 1).setStroke(); stem.stroke()
image.unlockFocus()
let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
