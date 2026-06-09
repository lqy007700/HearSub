import Foundation
import XCTest
@testable import HearSub

final class AppSettingsTests: XCTestCase {
    func testLegacySingleSourceSettingsDecodeIntoMultiSourceFields() throws {
        let json = """
        {
          "selectedSourceID": "mic-1",
          "inputLanguageID": "en",
          "outputLanguageID": "ja",
          "overlayStyle": {
            "translatedFontSize": 20,
            "sourceFontSize": 16,
            "backgroundOpacity": 0.7,
            "subtitleColor": { "kind": "defaultSubtitle" },
            "textColor": { "kind": "defaultText" },
            "backgroundColor": { "kind": "defaultBackground" },
            "showsTextOutline": true,
            "textOutlineColor": { "kind": "defaultTextOutline" },
            "attachToSource": true,
            "translatedFirst": true
          },
          "subtitleMode": "balanced",
          "subtitleDisplayMode": "both",
          "glossary": {}
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.selectedSourceID, "mic-1")
        XCTAssertEqual(settings.selectedSourceIDs, ["mic-1"])
        XCTAssertTrue(settings.sourceLanguageOverrides.isEmpty)
        XCTAssertTrue(settings.sourceOutputLanguageOverrides.isEmpty)
        XCTAssertEqual(settings.translationProvider, .openAICompatible)
        XCTAssertEqual(settings.openAICompatibleTranslation, .default)
    }

    func testMultiSourceSettingsRoundTripPreservesOverrides() throws {
        let settings = AppSettings(
            selectedSourceID: "mic-1",
            selectedSourceIDs: ["mic-1", "app-1"],
            sourceLanguageOverrides: ["app-1": "fr"],
            sourceOutputLanguageOverrides: ["mic-1": "zh-Hans", "app-1": "de"],
            inputLanguageID: "en",
            outputLanguageID: "ja",
            interfaceLanguageID: "en",
            overlayStyle: .default,
            subtitleMode: .balanced,
            subtitleDisplayMode: .both,
            translationProvider: .openAICompatible,
            openAICompatibleTranslation: OpenAICompatibleTranslationSettings(
                baseURL: "https://api.example.com",
                apiKey: "test-key",
                model: "fast-translator"
            )
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedSourceID, "mic-1")
        XCTAssertEqual(decoded.selectedSourceIDs, ["mic-1", "app-1"])
        XCTAssertEqual(decoded.sourceLanguageOverrides, ["app-1": "fr"])
        XCTAssertEqual(
            decoded.sourceOutputLanguageOverrides,
            ["mic-1": "zh-Hans", "app-1": "de"]
        )
        XCTAssertEqual(decoded.inputLanguageID, "en")
        XCTAssertEqual(decoded.outputLanguageID, "ja")
        XCTAssertEqual(decoded.interfaceLanguageID, "en")
        XCTAssertEqual(decoded.translationProvider, .openAICompatible)
        XCTAssertEqual(
            decoded.openAICompatibleTranslation,
            OpenAICompatibleTranslationSettings(
                baseURL: "https://api.example.com",
                apiKey: "test-key",
                model: "fast-translator"
            )
        )
    }

    func testOverlayStyleDecodesLegacySubtitleColorIntoSeparatedColors() throws {
        let json = """
        {
          "targetDisplayID": null,
          "topInset": 12,
          "widthRatio": 0.82,
          "minWidth": 720,
          "maxWidth": 1440,
          "backgroundOpacity": 0.32,
          "subtitleColor": { "red": 0.2, "green": 0.4, "blue": 0.8, "alpha": 1.0 },
          "backgroundColor": { "red": 0.0, "green": 0.0, "blue": 0.0, "alpha": 1.0 },
          "showsTextOutline": false,
          "textOutlineColor": { "red": 1.0, "green": 1.0, "blue": 1.0, "alpha": 1.0 },
          "translatedFontSize": 24,
          "sourceFontSize": 18,
          "clickThrough": true,
          "lineOrder": "sourceFirst",
          "overlayScaleFactor": 1.0,
          "attachToSource": false
        }
        """

        let style = try JSONDecoder().decode(OverlayStyle.self, from: Data(json.utf8))

        XCTAssertEqual(style.subtitleLayoutMode, .multiLine)
        XCTAssertEqual(style.subtitleColor, OverlayColor(red: 0.2, green: 0.4, blue: 0.8))
        XCTAssertEqual(style.translatedSubtitleColor, style.subtitleColor)
        XCTAssertEqual(style.sourceSubtitleColor, style.subtitleColor)
    }

    func testOverlayStyleRoundTripPreservesLayoutModeAndSeparatedColors() throws {
        let style = OverlayStyle(
            targetDisplayID: nil,
            topInset: 12,
            widthRatio: 0.82,
            minWidth: 720,
            maxWidth: 1440,
            backgroundOpacity: 0.32,
            subtitleColor: .defaultSubtitle,
            translatedSubtitleColor: OverlayColor(red: 0.9, green: 0.8, blue: 0.1),
            sourceSubtitleColor: OverlayColor(red: 0.2, green: 0.7, blue: 0.9),
            backgroundColor: .defaultBackground,
            showsTextOutline: false,
            textOutlineColor: .defaultTextOutline,
            translatedFontSize: 24,
            sourceFontSize: 18,
            clickThrough: true,
            lineOrder: .translationFirst,
            subtitleLayoutMode: .singleLine
        )

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(OverlayStyle.self, from: data)

        XCTAssertEqual(decoded.subtitleLayoutMode, .singleLine)
        XCTAssertEqual(decoded.translatedSubtitleColor, OverlayColor(red: 0.9, green: 0.8, blue: 0.1))
        XCTAssertEqual(decoded.sourceSubtitleColor, OverlayColor(red: 0.2, green: 0.7, blue: 0.9))
        XCTAssertEqual(decoded.lineOrder, .translationFirst)
    }
}
