import Foundation
import Translation

final class AppleTranslationService: Sendable {
    enum ServiceError: LocalizedError {
        case unavailable
        case resourcesNotInstalled
        case unsupportedLanguagePair

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Translation is unavailable on this macOS version."
            case .resourcesNotInstalled:
                "Apple Translation languages must be downloaded on-device."
            case .unsupportedLanguagePair:
                "Apple Translation does not support this language pair."
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

        let sourceLanguage = localeLanguage(for: sourceLanguageID)
        let targetLanguage = localeLanguage(for: targetLanguageID)
        let response = try await withStrategyFallback(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) { session in
            try await session.prepareTranslation()
            return try await session.translate(text)
        }
        return response.targetText
    }

    func prepareTranslation(
        from sourceLanguageID: String,
        to targetLanguageID: String
    ) async throws {
        guard #available(macOS 26.4, *) else {
            throw ServiceError.unavailable
        }

        let sourceLanguage = localeLanguage(for: sourceLanguageID)
        let targetLanguage = localeLanguage(for: targetLanguageID)
        try await withStrategyFallback(
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage
        ) { session in
            try await session.prepareTranslation()
        }
    }

    private func localeLanguage(for languageID: String) -> Locale.Language {
        Locale(identifier: LanguageCatalog.translationLocaleIdentifier(for: languageID)).language
    }

    @available(macOS 26.4, *)
    private func withStrategyFallback<T>(
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        operation: (TranslationSession) async throws -> T
    ) async throws -> T {
        do {
            let lowLatencySession = try await preparedSession(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                strategy: .lowLatency
            )
            return try await operation(lowLatencySession)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let highFidelitySession = try await preparedSession(
                sourceLanguage: sourceLanguage,
                targetLanguage: targetLanguage,
                strategy: .highFidelity
            )
            return try await operation(highFidelitySession)
        }
    }

    @available(macOS 26.4, *)
    private func preparedSession(
        sourceLanguage: Locale.Language,
        targetLanguage: Locale.Language,
        strategy: TranslationSession.Strategy
    ) async throws -> TranslationSession {
        let availability = LanguageAvailability(preferredStrategy: strategy)
        switch await availability.status(from: sourceLanguage, to: targetLanguage) {
        case .installed:
            return TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: strategy
            )
        case .supported:
            let session = TranslationSession(
                installedSource: sourceLanguage,
                target: targetLanguage,
                preferredStrategy: strategy
            )
            if session.canRequestDownloads {
                return session
            }
            throw ServiceError.resourcesNotInstalled
        case .unsupported:
            throw ServiceError.unsupportedLanguagePair
        @unknown default:
            throw ServiceError.unsupportedLanguagePair
        }
    }
}
