import Foundation
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updaterService: UpdaterService
    @ObservedObject var launchAtLoginService: LaunchAtLoginService
    let closeSettings: () -> Void
    let quitApp: () -> Void
    let openSubtitleModeInfo: () -> Void
    let showTranscript: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            TabView {
                transcriptionTab
                    .tabItem { Label(model.localized(.transcription), systemImage: "waveform") }
                translationTab
                    .tabItem { Label(model.localized(.translation), systemImage: "captions.bubble") }
                subtitlesTab
                    .tabItem { Label(model.localized(.subtitles), systemImage: "text.bubble") }
                advancedTab
                    .tabItem { Label(model.localized(.advanced), systemImage: "gearshape") }
            }
        }
        .frame(minWidth: 620, minHeight: 500)
        .environment(\.locale, model.interfaceLocale)
        .hearSubTranslationHost(model: model)
        .onChange(of: model.sessionState) { newState in
            if newState == .running {
                closeSettings()
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("HearSub")
                    .font(.headline)
                HStack(spacing: 6) {
                    Circle()
                        .fill(sessionDotColor)
                        .frame(width: 7, height: 7)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button {
                model.toggleSession()
            } label: {
                SessionActionButtonLabel(
                    title: model.sessionButtonTitle,
                    symbolName: model.sessionButtonSymbolName,
                    showsActivity: model.showsSessionWaitIndicator
                )
            }
            .buttonStyle(.borderedProminent)
            .tint(sessionActionTint)
            .controlSize(.regular)
            .disabled(model.isSessionButtonDisabled)
            Button(model.isOverlayVisible ? model.localized(.hideOverlay) : model.localized(.showSubtitlePreview)) {
                model.toggleOverlayVisibility()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Button(model.localized(.transcript)) {
                showTranscript()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            Button(model.localized(.quit)) {
                quitApp()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help(model.localized(.quit))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var sessionDotColor: Color {
        switch model.sessionState {
        case .idle: return .secondary
        case .running: return .green
        case .error: return .red
        }
    }

    private var sessionActionTint: Color {
        switch model.sessionState {
        case .idle: return .accentColor
        case .running, .error: return .red
        }
    }

    // MARK: - Transcription Tab

    private var transcriptionTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard {
                    sectionHeader(model.localized(.inputSource), icon: "mic.fill")
                    SettingsControlRow(label: model.localized(.selectedSource)) {
                        SourceMultiSelectPicker(
                            sources: model.allSources,
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            emptyTitle: model.allSources.isEmpty
                                ? model.localized(.noSourcesDetected)
                                : model.localized(.choose),
                            selection: model.selectedSourcesBinding
                        )
                    }
                    selectedSourceLanguageRows
                    SecondaryRefreshButton(
                        title: model.localized(.refreshSources),
                        action: model.refreshSources
                    )
                }
                settingsCard {
                    sectionHeader(model.localized(.languages), icon: "globe")
                    SettingsControlRow(label: model.localized(.defaultInputLanguage)) {
                        CommonLanguageMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            options: LanguageCatalog.speechInput,
                            selection: model.inputLanguageSelectionBinding
                        )
                        .disabled(model.isLanguagePairLocked)
                    }
                    Divider()
                    SettingsControlRow(label: model.localized(.defaultSubtitleLanguage)) {
                        CommonLanguageMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            selection: model.outputLanguageSelectionBinding
                        )
                        .disabled(model.isLanguagePairLocked)
                    }
                    Divider()
                    SettingsControlRow(label: model.localized(.subtitleMode)) {
                        HStack(spacing: 4) {
                            SubtitleModeMenuPicker(
                                interfaceLanguageID: model.resolvedInterfaceLanguageID,
                                showsDetail: true,
                                selection: model.subtitleModeSelectionBinding
                            )
                            Button(action: openSubtitleModeInfo) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(model.localized(.subtitleModeHelp))
                        }
                    }
                    Divider()
                    SettingsControlRow(label: model.localized(.subtitleDisplay)) {
                        SubtitleDisplayModeMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            selection: model.subtitleDisplayModeSelectionBinding
                        )
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Translation Tab

    private var translationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard {
                    sectionHeader(model.localized(.translationBackend), icon: "captions.bubble")
                    Text(model.localized(.openAICompatibleTranslationHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    SettingsControlRow(label: model.localized(.openAICompatibleBaseURL)) {
                        TextField("https://api.example.com", text: openAICompatibleBaseURLBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    SettingsControlRow(label: model.localized(.openAICompatibleAPIKey)) {
                        SecureField("sk-...", text: openAICompatibleAPIKeyBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 280)
                    }
                    SettingsControlRow(label: model.localized(.openAICompatibleModel)) {
                        if model.openAICompatibleModelOptions.isEmpty {
                            TextField("model-name", text: openAICompatibleModelBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 280)
                        } else {
                            Picker("", selection: openAICompatibleModelBinding) {
                                ForEach(model.openAICompatibleModelOptions, id: \.self) { modelID in
                                    Text(modelID).tag(modelID)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 280)
                        }
                    }
                    HStack {
                        Spacer()
                        Button {
                            model.testOpenAICompatibleTranslationConnection()
                        } label: {
                            if model.isTestingOpenAICompatibleConnection {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(model.localized(.testConnection), systemImage: "network")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.isTestingOpenAICompatibleConnection)

                        Button {
                            model.refreshOpenAICompatibleModels()
                        } label: {
                            if model.isFetchingOpenAICompatibleModels {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label(model.localized(.refreshModels), systemImage: "arrow.clockwise")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.isFetchingOpenAICompatibleModels)
                    }
                    if let error = model.openAICompatibleModelFetchError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let message = model.openAICompatibleConnectionTestMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(model.openAICompatibleConnectionTestSucceeded == true ? .green : .red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Subtitles Tab

    private var subtitlesTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard {
                    sectionHeader(model.localized(.subtitleOverlay), icon: "captions.bubble")
                    settingsRow(model.localized(.stopWhenHidingOverlay)) {
                        Toggle("", isOn: $model.stopsSessionWhenHidingOverlay)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    Text(model.localized(.stopWhenHidingOverlayHint))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                settingsCard {
                    sectionHeader(model.localized(.subtitleColor), icon: "paintpalette")
                    settingsRow(model.localized(.subtitleColor)) {
                        ColorPicker("", selection: subtitleColorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                    Divider()
                    settingsRow(model.localized(.backgroundColor)) {
                        ColorPicker("", selection: backgroundColorBinding, supportsOpacity: false)
                            .labelsHidden()
                    }
                    if !colorsUseDefaultValues {
                        HStack {
                            Spacer()
                            Button {
                                model.updateOverlayStyle { style in
                                    style.subtitleColor = .defaultSubtitle
                                    style.backgroundColor = .defaultBackground
                                }
                            } label: {
                                Label(model.localized(.resetColors), systemImage: "arrow.counterclockwise")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                settingsCard {
                    sectionHeader(model.localized(.translatedFont), icon: "textformat.size")
                    LabeledSlider(
                        title: model.localized(.translatedFont),
                        value: translatedFontBinding,
                        range: 8 ... 34,
                        precision: 0
                    )
                    LabeledSlider(
                        title: model.localized(.sourceFont),
                        value: sourceFontBinding,
                        range: 5 ... 28,
                        precision: 0
                    )
                }
            }
            .padding(20)
        }
    }

    // MARK: - Advanced Tab

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                settingsCard {
                    sectionHeader(model.localized(.general), icon: "gearshape")
                    settingsRow(model.localized(.sessionState)) {
                        Text(model.sessionBadgeText)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                    SettingsControlRow(label: model.localized(.interfaceLanguage)) {
                        CommonLanguageMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            selection: model.interfaceLanguageSelectionBinding
                        )
                    }
                }
                settingsCard {
                    sectionHeader(model.localized(.updates), icon: "arrow.triangle.2.circlepath")
                    settingsRow(model.localized(.openAtLogin)) {
                        Toggle("", isOn: launchAtLoginBinding)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    Divider()
                    settingsRow(model.localized(.checkForUpdatesAutomatically)) {
                        Toggle("", isOn: $updaterService.automaticallyChecksForUpdates)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    if launchAtLoginService.requiresApproval {
                        Text(model.localized(.enableAtLoginInSystemSettings))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button {
                                launchAtLoginService.openLoginItems()
                            } label: {
                                Label(model.localized(.openLoginItems), systemImage: "gearshape")
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let updateErrorMessage = launchAtLoginService.updateErrorMessage {
                        Text(model.localized(.launchAtLoginUpdateFailedFormat, updateErrorMessage))
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button {
                            updaterService.checkForUpdates()
                        } label: {
                            Label(model.localized(.checkForUpdates), systemImage: "arrow.clockwise")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                }
                VersionLink(
                    versionText: model.appVersionDisplayText,
                    repositoryURL: model.appRepositoryURL,
                    font: .caption.monospacedDigit()
                )
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(20)
        }
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.bottom, 4)
    }

    @ViewBuilder
    private func settingsRow<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            control()
        }
    }

    @ViewBuilder
    private func settingsCard<C: View>(@ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginService.launchesAtLogin },
            set: { launchAtLoginService.setLaunchesAtLogin($0) }
        )
    }

    private var translationProviderBinding: Binding<TranslationProvider> {
        Binding(
            get: { model.translationProvider },
            set: { model.translationProvider = $0 }
        )
    }

    private var openAICompatibleBaseURLBinding: Binding<String> {
        Binding(
            get: { model.openAICompatibleTranslation.baseURL },
            set: { newValue in
                var settings = model.openAICompatibleTranslation
                settings.baseURL = newValue
                model.openAICompatibleTranslation = settings
            }
        )
    }

    private var openAICompatibleAPIKeyBinding: Binding<String> {
        Binding(
            get: { model.openAICompatibleTranslation.apiKey },
            set: { newValue in
                var settings = model.openAICompatibleTranslation
                settings.apiKey = newValue
                model.openAICompatibleTranslation = settings
            }
        )
    }

    private var openAICompatibleModelBinding: Binding<String> {
        Binding(
            get: { model.openAICompatibleTranslation.model },
            set: { newValue in
                var settings = model.openAICompatibleTranslation
                settings.model = newValue
                model.openAICompatibleTranslation = settings
            }
        )
    }

    private var subtitleColorBinding: Binding<Color> {
        Binding(
            get: { model.overlayStyle.subtitleColor.color },
            set: { newColor in
                model.updateOverlayStyle { style in
                    style.subtitleColor = OverlayColor(color: newColor)
                }
            }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { model.overlayStyle.backgroundColor.color },
            set: { newColor in
                model.updateOverlayStyle { style in
                    style.backgroundColor = OverlayColor(color: newColor)
                }
            }
        )
    }

    private var translatedFontBinding: Binding<Double> {
        overlayBinding(\.translatedFontSize)
    }

    private var sourceFontBinding: Binding<Double> {
        overlayBinding(\.sourceFontSize)
    }

    @ViewBuilder private var selectedSourceLanguageRows: some View {
        let sources = model.selectedSources
        if sources.isEmpty == false {
            ForEach(sources) { source in
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text(source.name)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.primary)
                    SettingsControlRow(label: model.localized(.inputLanguage)) {
                        DefaultableLanguageMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            options: LanguageCatalog.speechInput,
                            defaultTitle: model.localized(
                                .useDefaultFormat,
                                model.languageName(for: model.inputLanguageID)
                            ),
                            selection: sourceLanguageBinding(for: source)
                        )
                        .disabled(model.isLanguagePairLocked)
                    }
                    SettingsControlRow(label: model.localized(.subtitleLanguage)) {
                        DefaultableLanguageMenuPicker(
                            interfaceLanguageID: model.resolvedInterfaceLanguageID,
                            defaultTitle: model.localized(
                                .useDefaultFormat,
                                model.languageName(for: model.outputLanguageID)
                            ),
                            selection: sourceOutputLanguageBinding(for: source)
                        )
                        .disabled(model.isLanguagePairLocked)
                    }
                }
            }
        }
    }

    private func sourceLanguageBinding(for source: InputSource) -> Binding<String?> {
        Binding(
            get: { model.languageOverrideID(for: source) },
            set: { model.setLanguageOverrideID($0, for: source) }
        )
    }

    private func sourceOutputLanguageBinding(for source: InputSource) -> Binding<String?> {
        Binding(
            get: { model.outputLanguageOverrideID(for: source) },
            set: { model.setOutputLanguageOverrideID($0, for: source) }
        )
    }

    private var colorsUseDefaultValues: Bool {
        model.overlayStyle.subtitleColor == .defaultSubtitle
            && model.overlayStyle.backgroundColor == .defaultBackground
    }

    private func overlayBinding<Value>(_ keyPath: WritableKeyPath<OverlayStyle, Value>) -> Binding<Value> {
        Binding(
            get: { model.overlayStyle[keyPath: keyPath] },
            set: { newValue in
                model.updateOverlayStyle { style in
                    style[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

struct LanguageResourceStatusListView: View {
    let statuses: [LanguageResourceStatus]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(statuses) { status in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(status.title)
                            .font(.caption.weight(.semibold))
                        Spacer()
                        if let progress = status.progress, status.isError == false {
                            Text("\(Int((progress * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }

                    if status.isError {
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if let progress = status.progress {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ProgressView()
                            .progressViewStyle(.linear)
                            .controlSize(.small)
                            .frame(maxWidth: .infinity)
                        Text(status.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}

private struct LabeledSlider: View {
    let title: String
    let value: Binding<Double>
    let range: ClosedRange<Double>
    let precision: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(formattedValue)
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    private var formattedValue: String {
        String(format: "%.\(precision)f", value.wrappedValue)
    }
}
