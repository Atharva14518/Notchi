import AppKit

enum BrandImages {
    static let menuBar: NSImage = {
        let image = NSImage(named: "MenuBarTemplate") ?? NSImage(size: NSSize(width: 18, height: 18))
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
