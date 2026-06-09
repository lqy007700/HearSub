import Foundation

final class TranscriptStore {
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = Self.defaultFileURL(fileName: "transcript.json")
        }
    }

    func load() -> PersistedTranscript {
        do {
            let data = try Data(contentsOf: fileURL)
            return try JSONDecoder().decode(PersistedTranscript.self, from: data)
        } catch {
            let nsError = error as NSError
            if nsError.domain != NSCocoaErrorDomain || nsError.code != NSFileReadNoSuchFileError {
                fputs("Failed to load transcript: \(error)\n", stderr)
            }
            return .empty
        }
    }

    func save(_ transcript: PersistedTranscript) {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: nil
            )

            let data = try JSONEncoder.prettyTranscript.encode(transcript)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            fputs("Failed to save transcript: \(error)\n", stderr)
        }
    }

    private static func defaultFileURL(fileName: String) -> URL {
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = appSupportRoot.appendingPathComponent("HearSub", isDirectory: true)
        return directory.appendingPathComponent(fileName)
    }
}

struct PersistedTranscript: Codable, Equatable {
    var entries: [TranscriptEntry]
    var sessions: [TranscriptSession]
    var sourceLanguageID: String?
    var targetLanguageID: String?

    static let empty = PersistedTranscript(
        entries: [],
        sessions: [],
        sourceLanguageID: nil,
        targetLanguageID: nil
    )

    private enum CodingKeys: String, CodingKey {
        case entries
        case sessions
        case sourceLanguageID
        case targetLanguageID
    }

    init(
        entries: [TranscriptEntry],
        sessions: [TranscriptSession],
        sourceLanguageID: String?,
        targetLanguageID: String?
    ) {
        self.entries = entries
        self.sessions = sessions
        self.sourceLanguageID = sourceLanguageID
        self.targetLanguageID = targetLanguageID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedSessions = try container.decodeIfPresent([TranscriptSession].self, forKey: .sessions) ?? []
        let decodedEntries = try container.decodeIfPresent([TranscriptEntry].self, forKey: .entries) ?? []
        sourceLanguageID = try container.decodeIfPresent(String.self, forKey: .sourceLanguageID)
        targetLanguageID = try container.decodeIfPresent(String.self, forKey: .targetLanguageID)

        if decodedSessions.isEmpty, decodedEntries.isEmpty == false {
            sessions = [
                TranscriptSession(
                    id: UUID(),
                    startedAt: Date.distantPast,
                    endedAt: nil,
                    title: nil,
                    sourceLanguageID: sourceLanguageID,
                    targetLanguageID: targetLanguageID,
                    entries: decodedEntries
                )
            ]
        } else {
            sessions = decodedSessions
        }
        entries = sessions.last?.entries ?? decodedEntries
    }
}

private extension JSONEncoder {
    static let prettyTranscript: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
