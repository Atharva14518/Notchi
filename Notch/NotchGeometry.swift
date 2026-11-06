import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: CGRect
    let topInset: CGFloat
    let notchWidth: CGFloat
    let centerX: CGFloat
    var contentHeight: CGFloat = PanelLayout.emptyHeight
    var preferredWidth: CGFloat = 420

    init(screenFrame: CGRect, topInset: CGFloat, leftArea: CGRect? = nil, rightArea: CGRect? = nil) {
        self.screenFrame = screenFrame
        if topInset > 0, let leftArea, let rightArea, rightArea.minX > leftArea.maxX {
            self.topInset = topInset
            notchWidth = rightArea.minX - leftArea.maxX
            centerX = (leftArea.maxX + rightArea.minX) / 2
        } else {
            self.topInset = 0
            notchWidth = 0
            centerX = screenFrame.midX
        }
    }

    init(screen: NSScreen) {
        self.init(screenFrame: screen.frame, topInset: screen.safeAreaInsets.top,
                  leftArea: screen.auxiliaryTopLeftArea, rightArea: screen.auxiliaryTopRightArea)
    }

    var hasNotch: Bool { notchWidth > 0 }
    var topGap: CGFloat { hasNotch ? 0 : 8 }
    var topEdge: CGFloat { screenFrame.maxY - topGap }
    var expandedSize: CGSize { CGSize(width: min(preferredWidth, screenFrame.width - 32), height: min(contentHeight + topInset, screenFrame.height - 32)) }
    var collapsedSize: CGSize { hasNotch ? CGSize(width: notchWidth, height: topInset) : CGSize(width: 170, height: 30) }
    var collapsedMetrics: SilhouetteMetrics {
        SilhouetteMetrics(size: collapsedSize, topRadius: hasNotch ? 0 : 15, bottomRadius: hasNotch ? 8 : 15)
    }
    var expandedMetrics: SilhouetteMetrics {
        SilhouetteMetrics(size: expandedSize, topRadius: hasNotch ? 0 : 24, bottomRadius: 24)
    }

    func frame(expanded: Bool) -> CGRect {
        let size = expanded ? expandedSize : collapsedSize
        return CGRect(x: centerX - size.width / 2, y: topEdge - size.height, width: size.width, height: size.height)
    }

    // A fixed canvas leaves space for spring overshoot. Its transparent areas pass clicks through.
    var canvasFrame: CGRect {
        let size = CGSize(width: expandedSize.width + 64, height: max(420 + topInset, expandedSize.height) + 40)
        return CGRect(x: centerX - size.width / 2, y: topEdge - size.height, width: size.width, height: size.height)
    }
    var hotZone: CGRect { frame(expanded: false).insetBy(dx: -12, dy: -8) }

    func globalFrame(for metrics: SilhouetteMetrics) -> CGRect {
        CGRect(x: centerX - metrics.size.width / 2, y: topEdge - metrics.size.height,
               width: metrics.size.width, height: metrics.size.height)
    }

    static func screenIndex(containing point: CGPoint, frames: [CGRect]) -> Int? {
        frames.firstIndex { $0.contains(point) }
    }
}
