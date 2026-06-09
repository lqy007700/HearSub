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
    var sourceLanguageID: String?
    var targetLanguageID: String?

    static let empty = PersistedTranscript(
        entries: [],
        sourceLanguageID: nil,
        targetLanguageID: nil
    )
}

private extension JSONEncoder {
    static let prettyTranscript: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
