import SwiftUI

struct SilhouetteMetrics: Equatable, Sendable {
    var size: CGSize
    var topRadius: CGFloat
    var bottomRadius: CGFloat
}

/// Width, height, and both corner radii share one interruptible SwiftUI transaction.
struct NotchSilhouette: Shape {
    var metrics: SilhouetteMetrics
    var onPresentation: (@Sendable (SilhouetteMetrics) -> Void)?

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(metrics.size.width, metrics.size.height), .init(metrics.topRadius, metrics.bottomRadius)) }
        set {
            metrics = SilhouetteMetrics(size: CGSize(width: newValue.first.first, height: newValue.first.second),
                                        topRadius: newValue.second.first, bottomRadius: newValue.second.second)
            onPresentation?(metrics)
        }
    }

    func path(in rect: CGRect) -> Path {
        let bounds = CGRect(x: rect.midX - metrics.size.width / 2, y: rect.minY,
                            width: max(0, metrics.size.width), height: max(0, metrics.size.height))
        return Self.outline(in: bounds, topRadius: metrics.topRadius, bottomRadius: metrics.bottomRadius)
    }

    static func outline(in r: CGRect, topRadius: CGFloat, bottomRadius: CGFloat) -> Path {
        let limit = min(r.width, r.height) / 2
        let top = min(max(topRadius, 0), limit)
        let bottom = min(max(bottomRadius, 0), limit)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY + top), control: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.maxX - bottom, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - bottom), control: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY), control: CGPoint(x: r.minX, y: r.minY))
        p.closeSubpath()
        return p
    }
}
