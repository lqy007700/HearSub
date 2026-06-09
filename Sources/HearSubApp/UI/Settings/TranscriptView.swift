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
        window.setContentSize(NSSize(width: 760, height: 520))
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
    @State private var selectedSessionID: UUID?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
            Divider()
            bottomBar
        }
        .frame(minWidth: 760, minHeight: 520)
        .environment(\.locale, model.interfaceLocale)
        .onAppear {
            syncSelectedSession()
        }
        .onChange(of: searchText) { _ in
            syncSelectedSession()
        }
        .onChange(of: model.transcriptGeneration) { _ in
            syncSelectedSession()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text(model.localized(.transcript))
                .font(.headline)
            Spacer()

            TextField(model.localized(.search), text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)

            Text("\(filteredSessions.count)/\(model.transcriptSessions.count)")
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

    private var content: some View {
        HStack(spacing: 0) {
            sessionList
                .frame(width: 260)
            Divider()
            sessionDetail
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                if filteredSessions.isEmpty {
                    Text("–")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20)
                } else {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                    }
                }
            }
            .padding(10)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    private func sessionRow(_ session: TranscriptSession) -> some View {
        Button {
            selectedSessionID = session.id
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(sessionTitle(session))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text("\(session.entries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(sessionDateRange(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let preview = sessionPreview(session) {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selectedSessionID == session.id ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selectedSessionID == session.id ? Color.accentColor.opacity(0.28) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                model.deleteTranscriptSession(id: session.id)
            } label: {
                Label(model.localized(.delete), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var sessionDetail: some View {
        if let selectedSession {
            VStack(spacing: 0) {
                detailHeader(selectedSession)
                Divider()
                transcriptList(selectedSession)
            }
        } else {
            Text("–")
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func detailHeader(_ session: TranscriptSession) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(sessionTitle(session))
                    .font(.headline)
                    .lineLimit(1)
                Text(sessionDateRange(session))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(session.entries.count) segments")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                model.deleteTranscriptSession(id: session.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.localized(.delete))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func transcriptList(_ session: TranscriptSession) -> some View {
        ScrollView {
            let entries = filteredEntries(in: session)
            if entries.isEmpty {
                Text("–")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(20)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(entries) { entry in
                        transcriptEntryRow(entry, sessionID: session.id)
                        Divider()
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
        }
    }

    private func transcriptEntryRow(_ entry: TranscriptEntry, sessionID: UUID) -> some View {
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
                model.deleteTranscriptEntry(id: entry.id, from: sessionID)
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
            .disabled(displayEntries.isEmpty)

            Button(model.localized(.clear)) {
                confirmDeleteSelectedSession()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .disabled(selectedSession == nil)

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Data Helpers

    private var displayText: String {
        displayEntries
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

    private var selectedSession: TranscriptSession? {
        guard let selectedSessionID else { return filteredSessions.first }
        return filteredSessions.first(where: { $0.id == selectedSessionID }) ?? filteredSessions.first
    }

    private var displayEntries: [TranscriptEntry] {
        guard let selectedSession else { return [] }
        return filteredEntries(in: selectedSession)
    }

    private var filteredSessions: [TranscriptSession] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return Array(model.transcriptSessions.reversed())
        }

        return Array(model.transcriptSessions.reversed()).filter { session in
            sessionTitle(session).localizedCaseInsensitiveContains(query)
                || session.entries.contains { entry in
                    entry.sourceText.localizedCaseInsensitiveContains(query)
                        || entry.translatedText.localizedCaseInsensitiveContains(query)
                }
        }
    }

    private func filteredEntries(in session: TranscriptSession) -> [TranscriptEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.isEmpty == false else {
            return session.entries
        }

        return session.entries.filter { entry in
            entry.sourceText.localizedCaseInsensitiveContains(query)
                || entry.translatedText.localizedCaseInsensitiveContains(query)
        }
    }

    private func syncSelectedSession() {
        let sessions = filteredSessions
        if let selectedSessionID,
           sessions.contains(where: { $0.id == selectedSessionID }) {
            return
        }
        selectedSessionID = sessions.first?.id
    }

    private func sessionTitle(_ session: TranscriptSession) -> String {
        if let title = session.title, title.isEmpty == false {
            return title
        }
        if session.startedAt == Date.distantPast {
            return "Imported transcript"
        }
        return Self.titleDateFormatter.string(from: session.startedAt)
    }

    private func sessionDateRange(_ session: TranscriptSession) -> String {
        guard session.startedAt != Date.distantPast else {
            return "\(session.entries.count) segments"
        }

        let start = Self.detailDateFormatter.string(from: session.startedAt)
        guard let endedAt = session.endedAt else {
            return "\(start) – Running"
        }
        return "\(start) – \(Self.timeFormatter.string(from: endedAt))"
    }

    private func sessionPreview(_ session: TranscriptSession) -> String? {
        session.entries.last?.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let titleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let detailDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

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

    private func confirmDeleteSelectedSession() {
        guard let selectedSession else { return }
        let alert = NSAlert()
        alert.messageText = model.localized(.clearTranscriptConfirmation)
        alert.addButton(withTitle: model.localized(.clear))
        alert.addButton(withTitle: model.localized(.done))
        alert.alertStyle = .warning

        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }

        model.deleteTranscriptSession(id: selectedSession.id)
    }
}
