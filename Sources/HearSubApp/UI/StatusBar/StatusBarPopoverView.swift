import SwiftUI

struct StatusBarPopoverView: View {
    @ObservedObject var model: AppModel
    let closePopover: () -> Void
    let openAdvancedSettings: () -> Void
    let showTranscript: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            configurationWarningSection
            sessionControls
            sourceSection
            displaySection
            settingsSection
        }
        .padding(14)
        .frame(width: 320)
        .environment(\.locale, model.interfaceLocale)
        .hearSubTranslationHost(model: model)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: StatusBarIconFactory.image(size: 24, template: false))
                .resizable()
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("HearSub")
                    .font(.headline)
                if model.sessionState == .running {
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    private var sessionControls: some View {
        Button {
            model.toggleSession()
        } label: {
            Label(
                model.sessionButtonTitle,
                systemImage: model.sessionButtonSymbolName
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(sessionActionTint)
        .controlSize(.large)
        .disabled(model.isSessionButtonDisabled)
    }

    @ViewBuilder
    private var configurationWarningSection: some View {
        if let warning = model.startupConfigurationWarnings.first {
            Button {
                openAdvancedSettings()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(10)
                .frame(maxWidth: .infinity)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Input Source

    private var sourceSection: some View {
        menuRow(title: model.localized(.inputSource), icon: "waveform") {
            SourceMultiSelectPicker(
                sources: model.allSources,
                interfaceLanguageID: model.resolvedInterfaceLanguageID,
                emptyTitle: model.allSources.isEmpty ? model.localized(.noSources) : model.localized(.choose),
                selection: model.selectedSourcesBinding
            )
        }
    }

    private var displaySection: some View {
        menuRow(title: model.localized(.subtitleDisplay), icon: "captions.bubble") {
            SubtitleDisplayModeMenuPicker(
                interfaceLanguageID: model.resolvedInterfaceLanguageID,
                selection: model.subtitleDisplayModeSelectionBinding
            )
        }
    }

    private var settingsSection: some View {
        Button {
            openAdvancedSettings()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .frame(width: 18)
                Text(model.localized(.settings))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func menuRow<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder control: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 18)
            Text(title)
                .font(.callout)
            Spacer()
            control()
                .labelsHidden()
        }
        .padding(10)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var sessionActionTint: Color {
        switch model.sessionState {
        case .idle: return .accentColor
        case .running, .error: return .red
        }
    }
}

struct VersionLink: View {
    let versionText: String
    let repositoryURL: URL?
    let font: Font

    var body: some View {
        versionLabel
            .help(versionText)
    }

    private var versionLabel: some View {
        Text(verbatim: versionText)
            .font(font)
            .foregroundStyle(.tertiary)
    }
}
