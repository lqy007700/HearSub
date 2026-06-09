import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - TranscriptWindowController

@MainActor
final class TranscriptWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        let window = NSWindow()
        let hostingController = NSHostingController(rootView: TranscriptView(model: model))
        window.contentViewController = hostingController
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 560, height: 520))
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        applyLocalizedTitle()
        model.$interfaceLanguageID
            .sink { [weak self] _ in self?.applyLocalizedTitle() }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showTranscript() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func applyLocalizedTitle() {
        window?.title = model.localized(.transcriptWindowTitle)
    }
}

// MARK: - TranscriptView

struct TranscriptView: View {
    @ObservedObject var model: AppModel
    @State private var showsTranslations = true
    @State private var searchText = ""
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            transcriptList
            Divider()
            bottomBar
        }
        .frame(minWidth: 520, minHeight: 480)
        .environment(\.locale, model.interfaceLocale)
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text(model.localized(.transcript))
                .font(.headline)
            Spacer()

            TextField(model.localized(.search), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)

            Text(model.localized(.transcriptCountFormat, filteredTranscriptEntries.count, model.transcriptEntries.count))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Toggle(model.localized(.translation), isOn: $showsTranslations)
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Content

    @ViewBuilder
    private var transcriptList: some View {
        ScrollView {
            if filteredTranscriptEntries.isEmpty {
                Text("–")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filteredTranscriptEntries) { entry in
                        transcriptEntryRow(entry)
                        Divider()
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
            }
        }
    }

    private func transcriptEntryRow(_ entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.sourceText.isEmpty ? "–" : entry.sourceText)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if showsTranslations, entry.translatedText.isEmpty == false {
                    Text(entry.translatedText)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                model.deleteTranscriptEntry(id: entry.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.localized(.delete))
        }
        .padding(.vertical, 10)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            Button(model.localized(.export)) {
                exportCurrentText()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(filteredTranscriptEntries.isEmpty)

            Button(model.localized(.clear)) {
                confirmClearTranscript()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(model.hasTranscript == false)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Data Helpers

    private var displayText: String {
        filteredTranscriptEntries
            .flatMap { entry -> [String] in
                if showsTranslations, entry.translatedText.isEmpty == false {
                    return [entry.sourceText, entry.translatedText]
                }
                return [entry.sourceText]
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
            .joined(separator: "\n")
    }

    private var filteredTranscriptEntries: [TranscriptEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return model.transcriptEntries
        }

        return model.transcriptEntries.filter { entry in
            entry.sourceText.localizedCaseInsensitiveContains(query)
                || entry.translatedText.localizedCaseInsensitiveContains(query)
        }
    }

    private func exportCurrentText() {
        exportError = nil
        let text = displayText
        guard text.isEmpty == false else { return }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HearSub Transcript.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func confirmClearTranscript() {
        let alert = NSAlert()
        alert.messageText = model.localized(.clearTranscriptConfirmation)
        alert.addButton(withTitle: model.localized(.clear))
        alert.addButton(withTitle: model.localized(.done))
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        model.clearTranscript()
    }
}
