import Foundation

enum TranslationProvider: String, Codable, CaseIterable, Identifiable {
    case apple
    case openAICompatible

    var id: String { rawValue }
}

struct OpenAICompatibleTranslationSettings: Codable, Equatable {
    var baseURL: String
    var apiKey: String
    var model: String

    static let `default` = OpenAICompatibleTranslationSettings(
        baseURL: "",
        apiKey: "",
        model: ""
    )
}

struct AppSettings: Codable {
    var selectedSourceID: String?
    var selectedSourceIDs: [String]
    var sourceLanguageOverrides: [String: String]
    var sourceOutputLanguageOverrides: [String: String]
    var inputLanguageID: String
    var outputLanguageID: String
    var interfaceLanguageID: String?
    var overlayStyle: OverlayStyle
    var subtitleMode: SubtitleMode
    var subtitleDisplayMode: SubtitleDisplayMode
    var glossary: [String: String]
    var translationProvider: TranslationProvider
    var openAICompatibleTranslation: OpenAICompatibleTranslationSettings
    var stopsSessionWhenHidingOverlay: Bool
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        selectedSourceID: nil,
        selectedSourceIDs: [],
        sourceLanguageOverrides: [:],
        sourceOutputLanguageOverrides: [:],
        inputLanguageID: "en",
        outputLanguageID: "zh-Hans",
        interfaceLanguageID: nil,
        overlayStyle: .default,
        subtitleMode: .balanced,
        subtitleDisplayMode: .both,
        glossary: [:],
        translationProvider: .openAICompatible,
        openAICompatibleTranslation: .default,
        stopsSessionWhenHidingOverlay: false,
        hasCompletedOnboarding: false
    )

    // Custom decoder so existing settings files load cleanly as new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedSourceID = try? c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        selectedSourceIDs = (try? c.decodeIfPresent([String].self, forKey: .selectedSourceIDs))
            ?? selectedSourceID.map { [$0] }
            ?? AppSettings.default.selectedSourceIDs
        sourceLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceLanguageOverrides))
            ?? AppSettings.default.sourceLanguageOverrides
        sourceOutputLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceOutputLanguageOverrides))
            ?? AppSettings.default.sourceOutputLanguageOverrides
        inputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .inputLanguageID))
            ?? AppSettings.default.inputLanguageID
        outputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .outputLanguageID))
            ?? AppSettings.default.outputLanguageID
        interfaceLanguageID = try? c.decodeIfPresent(String.self, forKey: .interfaceLanguageID)
        overlayStyle = (try? c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle))
            ?? AppSettings.default.overlayStyle
        subtitleMode = (try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode))
            ?? AppSettings.default.subtitleMode
        subtitleDisplayMode = (try? c.decodeIfPresent(SubtitleDisplayMode.self, forKey: .subtitleDisplayMode))
            ?? AppSettings.default.subtitleDisplayMode
        glossary = (try? c.decodeIfPresent([String: String].self, forKey: .glossary))
            ?? AppSettings.default.glossary
        translationProvider = (try? c.decodeIfPresent(TranslationProvider.self, forKey: .translationProvider))
            ?? AppSettings.default.translationProvider
        openAICompatibleTranslation = (
            try? c.decodeIfPresent(
                OpenAICompatibleTranslationSettings.self,
                forKey: .openAICompatibleTranslation
            )
        ) ?? AppSettings.default.openAICompatibleTranslation
        stopsSessionWhenHidingOverlay = (try? c.decodeIfPresent(Bool.self, forKey: .stopsSessionWhenHidingOverlay))
            ?? AppSettings.default.stopsSessionWhenHidingOverlay
        hasCompletedOnboarding = (try? c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding))
            ?? AppSettings.default.hasCompletedOnboarding
    }

    init(
        selectedSourceID: String?,
        selectedSourceIDs: [String] = [],
        sourceLanguageOverrides: [String: String] = [:],
        sourceOutputLanguageOverrides: [String: String] = [:],
        inputLanguageID: String,
        outputLanguageID: String,
        interfaceLanguageID: String?,
        overlayStyle: OverlayStyle,
        subtitleMode: SubtitleMode,
        subtitleDisplayMode: SubtitleDisplayMode,
        glossary: [String: String],
        translationProvider: TranslationProvider = .apple,
        openAICompatibleTranslation: OpenAICompatibleTranslationSettings = .default,
        stopsSessionWhenHidingOverlay: Bool = false,
        hasCompletedOnboarding: Bool = false
    ) {
        self.selectedSourceID = selectedSourceID
        self.selectedSourceIDs = selectedSourceIDs
        self.sourceLanguageOverrides = sourceLanguageOverrides
        self.sourceOutputLanguageOverrides = sourceOutputLanguageOverrides
        self.inputLanguageID  = inputLanguageID
        self.outputLanguageID = outputLanguageID
        self.interfaceLanguageID = interfaceLanguageID
        self.overlayStyle     = overlayStyle
        self.subtitleMode     = subtitleMode
        self.subtitleDisplayMode = subtitleDisplayMode
        self.glossary         = glossary
        self.translationProvider = translationProvider
        self.openAICompatibleTranslation = openAICompatibleTranslation
        self.stopsSessionWhenHidingOverlay = stopsSessionWhenHidingOverlay
        self.hasCompletedOnboarding = hasCompletedOnboarding
    }
}
