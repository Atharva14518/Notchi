import SwiftUI
import QuartzCore

/// Homography used to flatten the clipped source page into its corrected rectangle.
struct ScanPerspectiveEffect: GeometryEffect {
    var amount: CGFloat
    let quad: DocumentQuad
    var animatableData: CGFloat { get { amount } set { amount = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let source = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
        let rectangle = [CGPoint.zero, CGPoint(x: size.width, y: 0), CGPoint(x: size.width, y: size.height), CGPoint(x: 0, y: size.height)]
        let target = zip(source, rectangle).map { a, b in CGPoint(x: a.x + (b.x - a.x) * amount, y: a.y + (b.y - a.y) * amount) }
        return ProjectionTransform(Self.transform(source: source, target: target))
    }
    static func transform(source: [CGPoint], target: [CGPoint]) -> CATransform3D {
        guard source.count == 4, target.count == 4 else { return CATransform3DIdentity }
        var rows: [[CGFloat]] = []
        for (s, t) in zip(source, target) {
            rows.append([s.x, s.y, 1, 0, 0, 0, -t.x * s.x, -t.x * s.y, t.x])
            rows.append([0, 0, 0, s.x, s.y, 1, -t.y * s.x, -t.y * s.y, t.y])
        }
        for column in 0..<8 {
            let pivot = (column..<8).max { abs(rows[$0][column]) < abs(rows[$1][column]) }!
            guard abs(rows[pivot][column]) > 0.00000001 else { return CATransform3DIdentity }
            rows.swapAt(column, pivot)
            let divisor = rows[column][column]
            for j in column...8 { rows[column][j] /= divisor }
            for row in 0..<8 where row != column {
                let multiplier = rows[row][column]
                for j in column...8 { rows[row][j] -= multiplier * rows[column][j] }
            }
        }
        let h = (0..<8).map { rows[$0][8] }
        var matrix = CATransform3DIdentity
        matrix.m11 = h[0]; matrix.m21 = h[1]; matrix.m41 = h[2]
        matrix.m12 = h[3]; matrix.m22 = h[4]; matrix.m42 = h[5]
        matrix.m14 = h[6]; matrix.m24 = h[7]
        return matrix
    }
}
struct ScanQuadShape: Shape {
    var quad: DocumentQuad
    typealias Pair = AnimatablePair<CGFloat, CGFloat>
    typealias Four = AnimatablePair<Pair, Pair>
    var animatableData: AnimatablePair<Four, Four> {
        get { .init(.init(.init(quad.topLeft.x, quad.topLeft.y), .init(quad.topRight.x, quad.topRight.y)), .init(.init(quad.bottomRight.x, quad.bottomRight.y), .init(quad.bottomLeft.x, quad.bottomLeft.y))) }
        set {
            quad.topLeft = CGPoint(x: newValue.first.first.first, y: newValue.first.first.second)
            quad.topRight = CGPoint(x: newValue.first.second.first, y: newValue.first.second.second)
            quad.bottomRight = CGPoint(x: newValue.second.first.first, y: newValue.second.first.second)
            quad.bottomLeft = CGPoint(x: newValue.second.second.first, y: newValue.second.second.second)
        }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft].map { CGPoint(x: rect.minX + $0.x * rect.width, y: rect.minY + (1 - $0.y) * rect.height) }
        path.addLines(points); path.closeSubpath(); return path
    }
}
struct ScanPagePreview: View {
    let page: ScanPage
    let token: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = 0
    @State private var flatten: CGFloat = 0
    @State private var started = Date()
    var body: some View {
        GeometryReader { geometry in
            let image = phase >= 2 ? page.preview : page.originalPreview
            let rect = ScanCoordinates.fittedRect(imageSize: CGSize(width: image.width, height: image.height), canvas: geometry.size)
            ZStack {
                Image(decorative: page.originalPreview, scale: 1).resizable()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(ScanQuadShape(quad: phase == 0 ? .full : (page.quad ?? .full)))
                    .modifier(ScanPerspectiveEffect(amount: flatten, quad: page.quad ?? .full))
                    .opacity(phase >= 3 ? 0 : 1)
                Image(decorative: page.preview, scale: 1).resizable()
                    .frame(width: rect.width, height: rect.height).opacity(phase >= 3 ? 1 : 0)
                ScanQuadShape(quad: phase >= 2 ? .full : (page.quad ?? .full))
                    .stroke(Color.acid, style: StrokeStyle(lineWidth: 2, dash: phase == 0 ? [4, 3] : []))
                    .frame(width: rect.width, height: rect.height).opacity(phase == 1 || phase == 2 ? 1 : 0)
                if phase == 0 && !reduceMotion {
                    TimelineView(.animation(minimumInterval: Motion.frameInterval)) { context in
                        let amount = min(1, max(0, context.date.timeIntervalSince(started) / Motion.scanSweep))
                        Rectangle().fill(Color.acid).frame(width: rect.width, height: 2)
                            .shadow(color: .acid, radius: 6)
                            .offset(y: (CGFloat(amount) - 0.5) * rect.height)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .task(id: "\(page.id)-\(token)-\(reduceMotion)") {
            phase = reduceMotion ? 3 : 0; flatten = reduceMotion ? 1 : 0; started = Date()
            guard !reduceMotion else { return }
            do {
                try await Task.sleep(for: .seconds(Motion.scanSweep))
                withAnimation(Animations.snappy) { phase = 1 }
                try await Task.sleep(for: .seconds(Motion.scanCornerBeat))
                withAnimation(Animations.bouncy) { phase = 2; flatten = 1 }
                try await Task.sleep(for: .seconds(Motion.expandResponse))
                withAnimation(Animations.snappy) { phase = 3 }
            } catch { }
        }
        .accessibilityLabel(String(localized: "Processed document preview"))
    }
}
