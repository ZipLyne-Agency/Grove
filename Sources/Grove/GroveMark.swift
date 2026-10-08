import SwiftUI
import AppKit

/// Ask Grove's mark: two open growth rings, a core, and a bud. Geometry is on a 24 point grid.
struct GroveRings: Shape {
    var bud = true
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let innerStart = Angle.degrees(175).radians
        var rings = Path()
        rings.addArc(center: c, radius: 9 * s, startAngle: .degrees(350), endAngle: .degrees(280), clockwise: false)
        rings.move(to: CGPoint(x: c.x + 5.5 * s * CGFloat(cos(innerStart)), y: c.y + 5.5 * s * CGFloat(sin(innerStart))))
        rings.addArc(center: c, radius: 5.5 * s, startAngle: .degrees(175), endAngle: .degrees(95), clockwise: false)
        var mark = rings.strokedPath(StrokeStyle(lineWidth: 2.1 * s, lineCap: .round))
        mark.addEllipse(in: CGRect(x: c.x - 1.9 * s, y: c.y - 1.9 * s, width: 3.8 * s, height: 3.8 * s))
        if bud { mark.addEllipse(in: CGRect(x: c.x + 4.86 * s, y: c.y - 7.86 * s, width: 3 * s, height: 3 * s)) }
        return mark
    }
}

struct GroveMark: View {
    var size: CGFloat = 16
    var thinking = false
    var available = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turned = false
    private var spins: Bool { thinking && !reduceMotion }
    var body: some View {
        GroveRings(bud: available)
            .fill(available ? AnyShapeStyle(Color.ember) : AnyShapeStyle(.tertiary))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(spins && turned ? 360 : 0))
            .animation(spins ? .linear(duration: 2.4).repeatForever(autoreverses: false) : nil, value: turned)
            .opacity(thinking && reduceMotion ? 0.6 : 1)
            .onAppear { turned = spins }
            .onChange(of: spins) { turned = spins }
            .accessibilityHidden(true)
    }
}

/// Template image of the mark for native menus, which only draw images.
@MainActor enum GroveMarkImage {
    static let menu: NSImage = {
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        if let context = NSGraphicsContext.current?.cgContext {
            context.setFillColor(NSColor.black.cgColor)
            context.addPath(GroveRings().path(in: CGRect(x: 0, y: 0, width: 16, height: 16)).cgPath)
            context.fillPath()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }()
}

/// Ask Grove entry: the mark and words in ember on an ember wash.
struct AskGroveButtonStyle: ButtonStyle {
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .foregroundStyle(Color.ember)
            .padding(.leading, 8).padding(.trailing, 10)
            .frame(height: 28)
            .background(Color.ember.opacity(configuration.isPressed ? 0.24 : active ? 0.2 : 0.11), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .contentShape(Rectangle())
    }
}
