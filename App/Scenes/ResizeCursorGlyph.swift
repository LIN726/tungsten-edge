import SwiftUI

/// The ▲▼ "cursor" drawn while the pointer is over a taskbar grip zone or dragging the bar's
/// height. It is a real view in its own tiny panel, not an `NSCursor`: a background app cannot
/// change the system cursor, but it can hide it (`SystemCursorHider`) and draw its own glyph
/// under the pointer. Sized and drawn to read like the native Dock's divider cursor.
struct ResizeCursorGlyph: View {
    static let size = CGSize(width: 22, height: 30)

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let triangleWidth: CGFloat = 12, triangleHeight: CGFloat = 8, gap: CGFloat = 6
            let midX = w / 2, midY = h / 2
            var up = Path()
            up.move(to: CGPoint(x: midX, y: midY - gap / 2 - triangleHeight))
            up.addLine(to: CGPoint(x: midX + triangleWidth / 2, y: midY - gap / 2))
            up.addLine(to: CGPoint(x: midX - triangleWidth / 2, y: midY - gap / 2))
            up.closeSubpath()
            var down = Path()
            down.move(to: CGPoint(x: midX, y: midY + gap / 2 + triangleHeight))
            down.addLine(to: CGPoint(x: midX + triangleWidth / 2, y: midY + gap / 2))
            down.addLine(to: CGPoint(x: midX - triangleWidth / 2, y: midY + gap / 2))
            down.closeSubpath()
            for path in [up, down] {
                context.fill(path, with: .color(.white))
                context.stroke(path, with: .color(.black.opacity(0.85)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}
