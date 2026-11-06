import SwiftUI
import AppKit
import CoreText

enum Typography {
    enum Weight: String, CaseIterable {
        case regular = "Regular", medium = "Medium", semibold = "SemiBold"
        case bold = "Bold", extraBold = "ExtraBold", black = "Black"
        var postScriptName: String { "Poppins-\(rawValue)" }
    }
    // Register only in this process. Nothing is installed into the user's
    // Font Book or fetched at runtime; the OFL fonts ship in the app bundle.
    private static let registration: Void = registerFonts(in: .main)
    static func registerFonts(in bundle: Bundle) {
        for weight in Weight.allCases {
            guard let url = bundle.url(forResource: weight.postScriptName, withExtension: "ttf", subdirectory: "Fonts/Poppins") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
    static func registerFonts() { _ = registration }
    static func font(size: CGFloat, weight: Weight = .regular) -> Font {
        registerFonts()
        return .custom(weight.postScriptName, fixedSize: size)
    }
    static func appKitFont(size: CGFloat, weight: Weight = .regular) -> NSFont {
        registerFonts()
        return NSFont(name: weight.postScriptName, size: size) ?? .systemFont(ofSize: size)
    }

    static let wordmark = font(size: 17, weight: .black)
    static let settingsLabel = font(size: 13)
    static let settingsSection = font(size: 11, weight: .medium)
    static let title = font(size: 21, weight: .bold)
    static let display = font(size: 53, weight: .black)
    static let heading = font(size: 17, weight: .semibold)
    static let button = font(size: 12, weight: .semibold)
    static let body = font(size: 12)
    static let caption = font(size: 10, weight: .medium)
    static let eyebrow = font(size: 9, weight: .bold)
    // Retain the existing numeric-detail role, now using Poppins as well.
    static let mono = font(size: 10, weight: .medium)
}
