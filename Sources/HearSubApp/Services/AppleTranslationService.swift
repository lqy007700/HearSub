import Foundation
import Translation

final class AppleTranslationService: Sendable {
    enum ServiceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Translation is unavailable on this macOS version."
            }
        }
    }

    func translate(
        _ text: String,
        from sourceLanguageID: String,
        to targetLanguageID: String
    ) async throws -> String {
        guard #available(macOS 26.4, *) else {
            throw ServiceError.unavailable
        }

        let session = TranslationSession(
            installedSource: localeLanguage(for: sourceLanguageID),
            target: localeLanguage(for: targetLanguageID),
            preferredStrategy: .lowLatency
        )
        try await session.prepareTranslation()
        let response = try await session.translate(text)
        return response.targetText
    }

    func prepareTranslation(
        from sourceLanguageID: String,
        to targetLanguageID: String
    ) async throws {
        guard #available(macOS 26.4, *) else {
            throw ServiceError.unavailable
        }

        let session = TranslationSession(
            installedSource: localeLanguage(for: sourceLanguageID),
            target: localeLanguage(for: targetLanguageID),
            preferredStrategy: .lowLatency
        )
        try await session.prepareTranslation()
    }

    private func localeLanguage(for languageID: String) -> Locale.Language {
        Locale(identifier: languageID).language
    }
}
