import Foundation

enum InputSourceCategory: String, CaseIterable, Codable {
    case application
    case systemAudio
    case microphone

    func displayName(in languageID: String) -> String {
        switch self {
        case .application:
            return AppLocalization.string(.application, languageID: languageID)
        case .systemAudio:
            return AppLocalization.string(.macAudio, languageID: languageID)
        case .microphone:
            return AppLocalization.string(.microphone, languageID: languageID)
        }
    }
}

struct InputSource: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let detail: String
    let category: InputSourceCategory

    static let systemAudio = InputSource(
        id: "system-audio",
        name: AppLocalization.string(.macAudio, languageID: "en"),
        detail: "system-audio",
        category: .systemAudio
    )

    static let preview = InputSource(
        id: "preview",
        name: AppLocalization.string(.previewSource, languageID: "en"),
        detail: "preview",
        category: .microphone
    )
}
