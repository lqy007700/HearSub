import AppKit
import Foundation
import SwiftUI

struct OverlayColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let defaultSubtitle = OverlayColor(
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        alpha: 1.0
    )
    static let defaultBackground = OverlayColor(
        red: 0.0,
        green: 0.0,
        blue: 0.0,
        alpha: 1.0
    )
    static let defaultTextOutline = OverlayColor(
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        alpha: 1.0
    )

    init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1.0
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let srgbColor = NSColor(color).usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        self.init(
            red: Double(srgbColor.redComponent),
            green: Double(srgbColor.greenComponent),
            blue: Double(srgbColor.blueComponent),
            alpha: Double(srgbColor.alphaComponent)
        )
    }

    var color: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}

enum SubtitleLineOrder: String, Codable, CaseIterable, Identifiable {
    case sourceFirst
    case translationFirst

    var id: String { rawValue }
}

enum SubtitleLayoutMode: String, Codable, CaseIterable, Identifiable {
    case multiLine
    case singleLine

    var id: String { rawValue }

    func displayName(in languageID: String) -> String {
        switch self {
        case .multiLine:
            return AppLocalization.string(.subtitleLayoutMultiLine, languageID: languageID)
        case .singleLine:
            return AppLocalization.string(.subtitleLayoutSingleLine, languageID: languageID)
        }
    }
}

struct OverlayStyle: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case targetDisplayID
        case topInset
        case widthRatio
        case minWidth
        case maxWidth
        case backgroundOpacity
        case subtitleColor
        case translatedSubtitleColor
        case sourceSubtitleColor
        case backgroundColor
        case showsTextOutline = "usesWhiteTextOutline"
        case textOutlineColor
        case translatedFontSize
        case sourceFontSize
        case clickThrough
        case lineOrder
        case subtitleLayoutMode
        case overlayScaleFactor
        case attachToSource
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case usesHighContrastBorder
    }

    var targetDisplayID: String?
    var topInset: Double
    var widthRatio: Double
    var minWidth: Double
    var maxWidth: Double
    var backgroundOpacity: Double
    var subtitleColor: OverlayColor
    var translatedSubtitleColor: OverlayColor
    var sourceSubtitleColor: OverlayColor
    var backgroundColor: OverlayColor
    var showsTextOutline: Bool
    var textOutlineColor: OverlayColor
    var translatedFontSize: Double
    var sourceFontSize: Double
    var clickThrough: Bool
    var lineOrder: SubtitleLineOrder
    var subtitleLayoutMode: SubtitleLayoutMode
    var overlayScaleFactor: Double
    var attachToSource: Bool

    var scaledTranslatedFontSize: Double { translatedFontSize * overlayScaleFactor }
    var scaledSourceFontSize: Double { sourceFontSize * overlayScaleFactor }

    static let `default` = OverlayStyle(
        targetDisplayID: nil,
        topInset: 12,
        widthRatio: 0.82,
        minWidth: 720,
        maxWidth: 1440,
        backgroundOpacity: 0.32,
        subtitleColor: .defaultSubtitle,
        translatedSubtitleColor: .defaultSubtitle,
        sourceSubtitleColor: .defaultSubtitle,
        backgroundColor: .defaultBackground,
        showsTextOutline: false,
        textOutlineColor: .defaultTextOutline,
        translatedFontSize: 24,
        sourceFontSize: 18,
        clickThrough: true,
        lineOrder: .sourceFirst,
        subtitleLayoutMode: .multiLine,
        overlayScaleFactor: 1.0,
        attachToSource: false
    )

    init(
        targetDisplayID: String?,
        topInset: Double,
        widthRatio: Double,
        minWidth: Double,
        maxWidth: Double,
        backgroundOpacity: Double,
        subtitleColor: OverlayColor,
        translatedSubtitleColor: OverlayColor? = nil,
        sourceSubtitleColor: OverlayColor? = nil,
        backgroundColor: OverlayColor,
        showsTextOutline: Bool,
        textOutlineColor: OverlayColor,
        translatedFontSize: Double,
        sourceFontSize: Double,
        clickThrough: Bool,
        lineOrder: SubtitleLineOrder,
        subtitleLayoutMode: SubtitleLayoutMode = .multiLine,
        overlayScaleFactor: Double = 1.0,
        attachToSource: Bool = false
    ) {
        self.targetDisplayID = targetDisplayID
        self.topInset = topInset
        self.widthRatio = widthRatio
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.backgroundOpacity = backgroundOpacity
        self.subtitleColor = subtitleColor
        self.translatedSubtitleColor = translatedSubtitleColor ?? subtitleColor
        self.sourceSubtitleColor = sourceSubtitleColor ?? subtitleColor
        self.backgroundColor = backgroundColor
        self.showsTextOutline = showsTextOutline
        self.textOutlineColor = textOutlineColor
        self.translatedFontSize = translatedFontSize
        self.sourceFontSize = sourceFontSize
        self.clickThrough = clickThrough
        self.lineOrder = lineOrder
        self.subtitleLayoutMode = subtitleLayoutMode
        self.overlayScaleFactor = overlayScaleFactor
        self.attachToSource = attachToSource
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        targetDisplayID    = try c.decodeIfPresent(String.self, forKey: .targetDisplayID)
        topInset           = try c.decode(Double.self, forKey: .topInset)
        widthRatio         = try c.decode(Double.self, forKey: .widthRatio)
        minWidth           = try c.decode(Double.self, forKey: .minWidth)
        maxWidth           = try c.decode(Double.self, forKey: .maxWidth)
        backgroundOpacity  = try c.decode(Double.self, forKey: .backgroundOpacity)
        subtitleColor      = (try? c.decodeIfPresent(OverlayColor.self, forKey: .subtitleColor))
            ?? .defaultSubtitle
        translatedSubtitleColor = (try? c.decodeIfPresent(OverlayColor.self, forKey: .translatedSubtitleColor))
            ?? subtitleColor
        sourceSubtitleColor = (try? c.decodeIfPresent(OverlayColor.self, forKey: .sourceSubtitleColor))
            ?? subtitleColor
        backgroundColor    = (try? c.decodeIfPresent(OverlayColor.self, forKey: .backgroundColor))
            ?? .defaultBackground
        let legacyWhiteOutline = try legacy.decodeIfPresent(Bool.self, forKey: .usesHighContrastBorder)
        showsTextOutline = try c.decodeIfPresent(Bool.self, forKey: .showsTextOutline)
            ?? legacyWhiteOutline
            ?? false
        textOutlineColor  = (try? c.decodeIfPresent(OverlayColor.self, forKey: .textOutlineColor))
            ?? .defaultTextOutline
        translatedFontSize = try c.decode(Double.self, forKey: .translatedFontSize)
        sourceFontSize     = try c.decode(Double.self, forKey: .sourceFontSize)
        clickThrough       = try c.decode(Bool.self,   forKey: .clickThrough)
        lineOrder = try c.decodeIfPresent(SubtitleLineOrder.self, forKey: .lineOrder)
            ?? .sourceFirst
        subtitleLayoutMode = try c.decodeIfPresent(SubtitleLayoutMode.self, forKey: .subtitleLayoutMode)
            ?? .multiLine
        overlayScaleFactor = try c.decodeIfPresent(Double.self, forKey: .overlayScaleFactor) ?? 1.0
        attachToSource = try c.decodeIfPresent(Bool.self, forKey: .attachToSource) ?? false
    }
}
