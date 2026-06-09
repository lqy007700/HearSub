import AppKit
import SwiftUI

enum OverlayPanelMetrics {
    static let cornerRadius: CGFloat = 16
}

struct OverlayView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var interactionState: OverlayInteractionState
    var onMoveDragStart: () -> Void = {}
    var onMoveDragChanged: (CGSize) -> Void = { _ in }
    var onMoveDragEnded: () -> Void = {}
    @Namespace private var captionFlowNamespace
    @State private var renderedPassThroughBubble: OverlayPassThroughBubble?
    @State private var passThroughRevealProgress: Double = 0.0
    @State private var lastDraftSlotHeight: CGFloat = 0.0
    @State private var lastLiveLayersHeight: CGFloat = 0.0
    @State private var lastCommittedSlotHeight: CGFloat = 0.0
    @State private var measuredHistoryEntryHeights: [UUID: CGFloat] = [:]
    @State private var historyReviewViewportHeight: CGFloat = 0.0
    @State private var historyReviewContentHeight: CGFloat = 0.0

    var body: some View {
        ZStack {
            subtitleContent
                .mask(passThroughMask)

            OverlayLongPressDragLayer(
                onDragStart: onMoveDragStart,
                onDragChanged: onMoveDragChanged,
                onDragEnded: onMoveDragEnded,
                onHistoryScroll: { interactionState.scrollHistory(by: $0) },
                onHistoryReset: { interactionState.setHistoryScrollOffset(0) }
            )
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncPassThroughBubble(interactionState.passThroughBubble)
        }
        .onChange(of: interactionState.passThroughBubble) { bubble in
            syncPassThroughBubble(bubble)
        }
        .modifier(OverlayTranslationHostModifier(model: model))
    }

    @ViewBuilder
    private var subtitleContent: some View {
        Group {
            if let state = model.overlayState {
                GeometryReader { proxy in
                    let isReviewingHistory = interactionState.historyScrollOffset > 0.5
                    let availableHistoryHeight = availableHistoryHeight(for: proxy.size.height, state: state)
                    let visibleHistoryEntries = historyVisibleEntries(
                        from: state.history,
                        availableHeight: availableHistoryHeight,
                        reviewMode: false
                    )
                    let visibleHistoryCount = visibleHistoryEntries.count

                    ZStack(alignment: .bottom) {
                        if isReviewingHistory {
                            historyReviewLayer(state.history)
                        } else {
                            VStack(alignment: .center, spacing: Self.liveStackSpacing) {
                                ForEach(Array(visibleHistoryEntries.enumerated()), id: \.element.id) { index, entry in
                                    historyEntry(
                                        entry,
                                        index: index,
                                        totalCount: visibleHistoryEntries.count,
                                        reviewMode: false
                                    )
                                }

                                liveLayers(state)
                                    .background(liveLayersHeightReader)
                            }
                            .animation(
                                Self.captionFlowAnimation,
                                value: historyLayoutAnimationState(for: state, visibleHistoryEntries: visibleHistoryEntries)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .bottom)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .mask(continuousFlowMask)
                    .onAppear {
                        updateHistoryReviewViewportHeight(proxy.size.height)
                        syncHistoryReviewScrollBounds(for: state.history)
                    }
                    .onChange(of: proxy.size.height) { height in
                        updateHistoryReviewViewportHeight(height)
                        syncHistoryReviewScrollBounds(for: state.history)
                    }
                    .onPreferenceChange(DraftSlotHeightPreferenceKey.self) { height in
                        guard height > 0 else { return }
                        let snappedHeight = ceil(height)
                        let downwardDelta = lastDraftSlotHeight - snappedHeight

                        if lastDraftSlotHeight == 0
                            || snappedHeight >= lastDraftSlotHeight
                            || downwardDelta >= Self.draftHeightJitterTolerance {
                            lastDraftSlotHeight = snappedHeight
                        }
                    }
                    .onPreferenceChange(LiveLayersHeightPreferenceKey.self) { height in
                        guard height > 0 else { return }
                        lastLiveLayersHeight = ceil(height)
                    }
                    .onPreferenceChange(CommittedSlotHeightPreferenceKey.self) { height in
                        guard height > 0 else { return }
                        lastCommittedSlotHeight = ceil(height)
                    }
                    .onPreferenceChange(HistoryEntryHeightsPreferenceKey.self) { heights in
                        guard heights.isEmpty == false else { return }
                        for (id, height) in heights where height > 0 {
                            measuredHistoryEntryHeights[id] = ceil(height)
                        }
                    }
                    .onPreferenceChange(HistoryReviewContentHeightPreferenceKey.self) { height in
                        let snappedHeight = ceil(height)
                        guard abs(historyReviewContentHeight - snappedHeight) > 0.5 else { return }
                        historyReviewContentHeight = snappedHeight
                        syncHistoryReviewScrollBounds(for: state.history)
                    }
                    .onAppear {
                        model.updateOverlayHistoryVisibleCount(visibleHistoryCount)
                    }
                    .onChange(of: visibleHistoryCount) { newCount in
                        model.updateOverlayHistoryVisibleCount(newCount)
                    }
                    .onChange(of: state.history.map(\.id)) { ids in
                        let validIDs = Set(ids)
                        measuredHistoryEntryHeights = measuredHistoryEntryHeights.filter { validIDs.contains($0.key) }
                        syncHistoryReviewScrollBounds(for: state.history)
                    }
                    .onChange(of: state.history.count) { _ in
                        model.updateOverlayHistoryVisibleCount(visibleHistoryCount)
                        syncHistoryReviewScrollBounds(for: state.history)
                    }
                    .onChange(of: model.sessionState) { newState in
                        if newState != .running {
                            lastDraftSlotHeight = 0
                            lastLiveLayersHeight = 0
                            lastCommittedSlotHeight = 0
                            measuredHistoryEntryHeights = [:]
                        }
                    }
                }
                .padding(.leading, 20)
                .padding(.trailing, 20 + OverlayHistoryScrollbarLayout.panelWidth + OverlayHistoryScrollbarLayout.contentSpacing)
                // Keep breathing room at the top, but let the live draft stack
                // spend the full bottom edge budget when the window is shrunk.
                .padding(.top, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(backgroundView)
                .overlay(
                    RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            }
        }
        .padding(.horizontal, OverlayControlsLayout.outerPadding)
        .padding(.vertical, OverlayControlsLayout.outerPadding)
    }

    // MARK: - Continuous flow

    private func historyReviewLayer(_ history: [OverlayHistoryEntry]) -> some View {
        VStack(alignment: .center, spacing: Self.liveStackSpacing) {
            ForEach(Array(history.enumerated()), id: \.element.id) { index, entry in
                historyEntry(
                    entry,
                    index: index,
                    totalCount: history.count,
                    reviewMode: true
                )
            }
        }
        .background(historyReviewContentHeightReader)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .bottom)
        .offset(y: interactionState.historyScrollOffset)
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    private func liveLayers(_ state: OverlayPreviewState) -> some View {
        VStack(alignment: .center, spacing: Self.liveStackSpacing) {
            if hasCommittedCaption(state) {
                committedLayer(state)
            } else if shouldReserveCommittedSlot(for: state) {
                committedSlotPlaceholder
            }

            draftLayer(state)
        }
        .animation(Self.captionFlowAnimation, value: flowAnimationState(for: state))
    }

    private func committedLayer(_ state: OverlayPreviewState) -> some View {
        applyingPromotionTransition(
            to: captionPair(
                translated: state.translatedText,
                translatedColor: baseSubtitleColor,
                source: state.sourceText,
                sourceColor: subtitleColor(opacity: 0.82)
            )
            .background(committedSlotHeightReader),
            key: promotionKey(
                promotionID: state.committedPromotionID,
                sourceText: state.sourceText,
                translatedText: state.translatedText
            )
        )
    }

    private func translatedText(_ text: String, color: Color) -> some View {
        captionText(
            attributedCaptionText(
                text: text,
                fillColor: color
            ),
            rawText: text,
            fontSize: model.overlayStyle.scaledTranslatedFontSize,
            weight: .semibold
        )
    }

    private func sourceText(_ text: String, color: Color) -> some View {
        captionText(
            attributedCaptionText(
                text: text,
                fillColor: color
            ),
            rawText: text,
            fontSize: displayedSourceFontSize,
            weight: displayedSourceFontWeight
        )
    }

    // MARK: - Draft layer (50–65% opacity, stable prefix slightly brighter)

    private func draftLayer(_ state: OverlayPreviewState) -> some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if let draftText = state.draftSourceText, !draftText.isEmpty {
                let visibleDraftTranslatedText = displayedDraftTranslatedText(
                    for: state,
                    draftText: draftText
                )
                applyingPromotionTransition(
                    to: VStack(spacing: 2) {
                        if showsTranslatedSubtitle {
                            if let draftTranslated = visibleDraftTranslatedText {
                                translatedText(
                                    draftTranslated,
                                    color: subtitleColor(opacity: 0.55)
                                )
                            } else if model.shouldReserveDraftTranslationSlot {
                                Text(" ")
                                    .font(.system(size: model.overlayStyle.scaledTranslatedFontSize, weight: .semibold))
                                    .multilineTextAlignment(.center)
                                    .lineLimit(nil)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity)
                                    .hidden()
                                    .accessibilityHidden(true)
                            }
                        }

                        if showsOriginalSubtitle {
                            let prefixLen = min(state.draftStablePrefixLength, draftText.count)
                            let stable = String(draftText.prefix(prefixLen))
                            let mutable = String(draftText.dropFirst(prefixLen))

                            captionText(
                                draftSourceAttributedText(
                                    stable: stable,
                                    mutable: mutable
                                ),
                                rawText: draftText,
                                fontSize: displayedSourceFontSize,
                                weight: displayedSourceFontWeight
                            )
                        }
                    }
                    .background(draftSlotHeightReader),
                    key: promotionKey(
                        promotionID: state.draftPromotionID,
                        sourceText: draftText,
                        translatedText: visibleDraftTranslatedText ?? draftText
                    )
                )
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(
            maxWidth: .infinity,
            minHeight: draftSlotHeight(for: state),
            maxHeight: draftSlotHeight(for: state),
            alignment: .top
        )
    }

    private func historyEntry(
        _ entry: OverlayHistoryEntry,
        index: Int,
        totalCount: Int,
        reviewMode: Bool
    ) -> some View {
        let ageProgress = totalCount > 1
            ? Double(index) / Double(totalCount - 1)
            : 1.0
        let translatedOpacity = reviewMode ? 0.94 : 0.34 + (0.34 * ageProgress)
        let sourceOpacity = reviewMode ? 0.68 : 0.22 + (0.24 * ageProgress)

        return captionPair(
            translated: entry.translatedText,
            translatedColor: subtitleColor(opacity: translatedOpacity),
            source: entry.sourceText,
            sourceColor: subtitleColor(opacity: sourceOpacity)
        )
        .background(historyEntryHeightReader(for: entry.id))
    }

    private func historyVisibleEntries(
        from history: [OverlayHistoryEntry],
        availableHeight: CGFloat,
        reviewMode: Bool
    ) -> [OverlayHistoryEntry] {
        guard availableHeight > 0 else { return [] }
        let offset = 0
        let upperBound = max(0, history.count - offset)
        guard upperBound > 0 else { return [] }

        var lowerBound = upperBound
        var consumedHeight: CGFloat = 0

        while lowerBound > 0 {
            let entry = history[lowerBound - 1]
            let nextHeight = historyEntryHeight(for: entry) + Self.liveStackSpacing
            if lowerBound == upperBound || consumedHeight + nextHeight <= availableHeight {
                consumedHeight += nextHeight
                lowerBound -= 1
            } else {
                break
            }
        }

        return Array(history[lowerBound..<upperBound])
    }

    private func availableHistoryHeight(for height: CGFloat, state: OverlayPreviewState) -> CGFloat {
        max(height - reservedFlowHeight(for: state), 0)
    }

    private func reservedFlowHeight(for state: OverlayPreviewState) -> CGFloat {
        max(lastLiveLayersHeight, estimatedLiveLayersHeight(for: state))
    }

    private func hasCommittedCaption(_ state: OverlayPreviewState) -> Bool {
        usesSourceAsTranslationFallback(
            translated: state.translatedText,
            source: state.sourceText
        )
            || (showsTranslatedSubtitle && state.translatedText.isEmpty == false)
            || (showsOriginalSubtitle && state.sourceText.isEmpty == false)
    }

    private func shouldReserveCommittedSlot(for state: OverlayPreviewState) -> Bool {
        hasCommittedCaption(state) || model.shouldReserveCommittedCaptionSlot
    }

    private func flowAnimationState(for state: OverlayPreviewState) -> OverlayFlowAnimationState {
        OverlayFlowAnimationState(
            captionEpoch: state.captionEpoch,
            translatedText: state.translatedText,
            sourceText: state.sourceText,
            committedPromotionID: state.committedPromotionID,
            draftPromotionID: state.draftPromotionID,
            reservesCommittedSlot: shouldReserveCommittedSlot(for: state)
        )
    }

    private func historyLayoutAnimationState(
        for state: OverlayPreviewState,
        visibleHistoryEntries: [OverlayHistoryEntry]
    ) -> OverlayHistoryLayoutAnimationState {
        OverlayHistoryLayoutAnimationState(
            historyIDs: visibleHistoryEntries.map(\.id),
            reservesCommittedSlot: shouldReserveCommittedSlot(for: state),
            draftPromotionID: state.draftPromotionID
        )
    }

    private var estimatedCommittedSlotHeight: CGFloat {
        estimatedCaptionPairHeight(
            showsTranslated: showsTranslatedSubtitle,
            showsSource: showsOriginalSubtitle
        )
    }

    private var committedSlotHeight: CGFloat {
        max(lastCommittedSlotHeight, estimatedCommittedSlotHeight)
    }

    private func historyEntryHeight(for entry: OverlayHistoryEntry) -> CGFloat {
        max(measuredHistoryEntryHeights[entry.id] ?? 0, estimatedHistoryEntryHeight(for: entry))
    }

    private func estimatedHistoryEntryHeight(for entry: OverlayHistoryEntry) -> CGFloat {
        let usesFallback = usesSourceAsTranslationFallback(
            translated: entry.translatedText,
            source: entry.sourceText
        )
        return estimatedCaptionPairHeight(
            showsTranslated: showsTranslatedSubtitle,
            showsSource: showsOriginalSubtitle && entry.sourceText.isEmpty == false && usesFallback == false
        )
    }

    private func estimatedLiveLayersHeight(for state: OverlayPreviewState) -> CGFloat {
        var height = draftSlotHeight(for: state)

        if shouldReserveCommittedSlot(for: state) {
            height += committedSlotHeight + Self.liveStackSpacing
        }

        return height
    }

    private func draftSlotHeight(for state: OverlayPreviewState) -> CGFloat {
        max(lastDraftSlotHeight, estimatedDraftRowHeight(for: state)) + Self.draftBottomInset
    }

    private func estimatedDraftRowHeight(for state: OverlayPreviewState) -> CGFloat {
        let currentDraftTranslation = state.visibleDraftTranslatedText(
            for: state.draftSourceText ?? "",
            promotionID: state.draftPromotionID
        )
        let translatedHeight = showsTranslatedSubtitle && (
            (currentDraftTranslation?.isEmpty == false) || model.shouldReserveDraftTranslationSlot
        )
            ? translatedLineHeight
            : 0
        let sourceHeight = showsOriginalSubtitle ? sourceLineHeight : 0
        return translatedHeight + sourceHeight
    }

    private func displayedDraftTranslatedText(
        for state: OverlayPreviewState,
        draftText: String
    ) -> String? {
        if model.shouldReserveDraftTranslationSlot && showsOriginalSubtitle == false {
            return draftText
        }

        guard let draftTranslated = state.visibleDraftTranslatedText(
            for: draftText,
            promotionID: state.draftPromotionID
        ),
              draftTranslated.isEmpty == false else {
            return nil
        }

        return draftTranslated
    }

    private var draftSlotHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: DraftSlotHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var committedSlotPlaceholder: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: committedSlotHeight)
            .accessibilityHidden(true)
    }

    private var liveLayersHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: LiveLayersHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private var committedSlotHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: CommittedSlotHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private func historyEntryHeightReader(for id: UUID) -> some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: HistoryEntryHeightsPreferenceKey.self, value: [id: proxy.size.height])
        }
    }

    private var historyReviewContentHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .preference(key: HistoryReviewContentHeightPreferenceKey.self, value: proxy.size.height)
        }
    }

    private func updateHistoryReviewViewportHeight(_ height: CGFloat) {
        let snappedHeight = ceil(height)
        guard abs(historyReviewViewportHeight - snappedHeight) > 0.5 else { return }
        historyReviewViewportHeight = snappedHeight
    }

    private func syncHistoryReviewScrollBounds(for history: [OverlayHistoryEntry]) {
        let estimatedContentHeight = estimatedHistoryReviewContentHeight(for: history)
        let contentHeight = max(historyReviewContentHeight, estimatedContentHeight)
        interactionState.updateHistoryScrollMetrics(
            contentHeight: contentHeight,
            viewportHeight: historyReviewViewportHeight
        )
    }

    private func estimatedHistoryReviewContentHeight(for history: [OverlayHistoryEntry]) -> CGFloat {
        guard history.isEmpty == false else { return 0 }
        let entriesHeight = history.reduce(CGFloat(0)) { partial, entry in
            partial + historyEntryHeight(for: entry)
        }
        return entriesHeight + (Self.liveStackSpacing * CGFloat(max(history.count - 1, 0)))
    }

    private func promotionKey(
        promotionID: UUID?,
        sourceText: String,
        translatedText: String
    ) -> String? {
        if let promotionID {
            return "live-caption:\(promotionID.uuidString)"
        }

        let normalizedSource = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSource.isEmpty == false {
            return "live-caption:\(normalizedSource)"
        }

        let normalizedTranslation = translatedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedTranslation.isEmpty == false else { return nil }
        return "live-caption:\(normalizedTranslation)"
    }

    @ViewBuilder
    private func applyingPromotionTransition<Content: View>(
        to content: Content,
        key: String?
    ) -> some View {
        if let key {
            content.matchedGeometryEffect(
                id: key,
                in: captionFlowNamespace,
                properties: .frame,
                anchor: .bottom
            )
        } else {
            content
        }
    }

    private func captionPair(
        translated: String,
        translatedColor: Color,
        source: String,
        sourceColor: Color
    ) -> some View {
        let usesFallback = usesSourceAsTranslationFallback(
            translated: translated,
            source: source
        )
        let primaryTranslatedText = usesFallback ? source : translated
        let showsSourceLine = showsOriginalSubtitle && source.isEmpty == false && usesFallback == false

        return VStack(spacing: Self.captionPairSpacing) {
            if model.overlayStyle.translatedFirst {
                if showsTranslatedSubtitle {
                    translatedText(
                        primaryTranslatedText,
                        color: translatedColor
                    )
                }

                if showsSourceLine {
                    sourceText(
                        source,
                        color: sourceColor
                    )
                }
            } else {
                if showsSourceLine {
                    sourceText(
                        source,
                        color: sourceColor
                    )
                }

                if showsTranslatedSubtitle {
                    translatedText(
                        primaryTranslatedText,
                        color: translatedColor
                    )
                }
            }
        }
    }

    /// usesSourceAsTranslationFallback
    /// Returns true when a translated slot should show source text while translation is pending.
    private func usesSourceAsTranslationFallback(translated: String, source: String) -> Bool {
        showsTranslatedSubtitle && translated.isEmpty && source.isEmpty == false
    }

    private var showsOriginalSubtitle: Bool {
        model.showsOriginalSubtitle
    }

    private var showsTranslatedSubtitle: Bool {
        model.showsTranslatedSubtitle
    }

    private var translatedLineHeight: CGFloat {
        CGFloat(model.overlayStyle.scaledTranslatedFontSize + 10.0)
    }

    private var sourceLineHeight: CGFloat {
        if usesTranslatedTypographyForSourceText {
            return translatedLineHeight
        }

        return CGFloat(model.overlayStyle.scaledSourceFontSize + 14.0)
    }

    private var usesTranslatedTypographyForSourceText: Bool {
        showsOriginalSubtitle && !showsTranslatedSubtitle
    }

    private var displayedSourceFontSize: Double {
        usesTranslatedTypographyForSourceText
            ? model.overlayStyle.scaledTranslatedFontSize
            : model.overlayStyle.scaledSourceFontSize
    }

    private var displayedSourceFontWeight: Font.Weight {
        usesTranslatedTypographyForSourceText ? .semibold : .regular
    }

    private func estimatedCaptionPairHeight(
        showsTranslated: Bool,
        showsSource: Bool
    ) -> CGFloat {
        let translatedHeight = showsTranslated ? translatedLineHeight : 0
        let sourceHeight = showsSource ? sourceLineHeight : 0
        let spacingHeight = (showsTranslated && showsSource) ? Self.captionPairSpacing : 0
        return translatedHeight + spacingHeight + sourceHeight
    }

    private var continuousFlowMask: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0.0),
                .init(color: .white.opacity(0.8), location: 0.10),
                .init(color: .white, location: 0.22),
                .init(color: .white, location: 1.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Background

    private var backgroundView: some View {
        RoundedRectangle(cornerRadius: OverlayPanelMetrics.cornerRadius, style: .continuous)
            .fill(baseBackgroundColor.opacity(model.overlayStyle.backgroundOpacity))
    }

    private func captionText(
        _ attributedText: AttributedString,
        rawText: String,
        fontSize: Double,
        weight: Font.Weight
    ) -> some View {
        ZStack {
            if model.overlayStyle.showsTextOutline, rawText.isEmpty == false {
                outlineText(
                    rawText,
                    fontSize: fontSize,
                    weight: weight
                )
            }

            Text(attributedText)
                .font(.system(size: fontSize, weight: weight))
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
    }

    private func attributedCaptionText(
        text: String,
        fillColor: Color
    ) -> AttributedString {
        var attributed = AttributedString(text)
        attributed.foregroundColor = fillColor
        return attributed
    }

    private func draftSourceAttributedText(
        stable: String,
        mutable: String
    ) -> AttributedString {
        var attributed = AttributedString()

        if stable.isEmpty == false {
            var stablePart = AttributedString(stable)
            stablePart.foregroundColor = subtitleColor(opacity: 0.62)
            attributed += stablePart
        }

        if mutable.isEmpty == false {
            var mutablePart = AttributedString(mutable)
            mutablePart.foregroundColor = subtitleColor(opacity: 0.48)
            attributed += mutablePart
        }

        return attributed
    }

    private func outlineText(
        _ text: String,
        fontSize: Double,
        weight: Font.Weight
    ) -> some View {
        ZStack {
            ForEach(Self.textOutlineOffsets.indices, id: \.self) { index in
                let offset = Self.textOutlineOffsets[index]
                Text(text)
                    .font(.system(size: fontSize, weight: weight))
                    .foregroundStyle(baseTextOutlineColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .offset(x: offset.width, y: offset.height)
            }
        }
    }

    private var baseSubtitleColor: Color {
        model.overlayStyle.subtitleColor.color
    }

    private var baseBackgroundColor: Color {
        model.overlayStyle.backgroundColor.color
    }

    private var baseTextOutlineColor: Color {
        model.overlayStyle.textOutlineColor.color
    }

    private func subtitleColor(opacity: Double) -> Color {
        baseSubtitleColor.opacity(opacity)
    }

    @ViewBuilder
    private var passThroughBubble: some View {
        if let hint = renderedPassThroughBubble {
            OverlayPassThroughBubbleView()
                .frame(width: hint.diameter, height: hint.diameter)
                .position(x: hint.center.x, y: hint.center.y)
                .scaleEffect(0.92 + (0.08 * passThroughRevealProgress))
                .opacity(passThroughRevealProgress)
                .allowsHitTesting(false)
        }
    }

    private var passThroughMask: some View {
        Rectangle()
            .fill(Color.white)
            .overlay {
                if let hint = renderedPassThroughBubble {
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: 0.38),
                                    .init(color: .black.opacity(0.68), location: 0.58),
                                    .init(color: .black.opacity(0.28), location: 0.76),
                                    .init(color: .clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: hint.diameter * 0.5
                            )
                        )
                        .frame(width: hint.diameter, height: hint.diameter)
                        .position(x: hint.center.x, y: hint.center.y)
                        .scaleEffect(0.92 + (0.08 * passThroughRevealProgress))
                        .opacity(passThroughRevealProgress)
                        .blendMode(.destinationOut)
                }
            }
            .compositingGroup()
    }

    private func syncPassThroughBubble(_ bubble: OverlayPassThroughBubble?) {
        if let bubble {
            renderedPassThroughBubble = bubble

            guard passThroughRevealProgress < 1.0 else { return }
            withAnimation(Self.passThroughTransitionAnimation) {
                passThroughRevealProgress = 1.0
            }
            return
        }

        guard renderedPassThroughBubble != nil else { return }
        withAnimation(Self.passThroughTransitionAnimation) {
            passThroughRevealProgress = 0.0
        }
    }
}

private extension OverlayView {
    static let captionFlowAnimation = Animation.interactiveSpring(
        response: 0.32,
        dampingFraction: 0.88,
        blendDuration: 0.08
    )
    static let liveStackSpacing: CGFloat = 10.0
    static let draftBottomInset: CGFloat = 3.0
    static let draftHeightJitterTolerance: CGFloat = 6.0
    static let captionPairSpacing: CGFloat = 4.0
    static let textOutlineOffsets: [CGSize] = [
        CGSize(width: -1, height: 0),
        CGSize(width: 1, height: 0),
        CGSize(width: 0, height: -1),
        CGSize(width: 0, height: 1),
        CGSize(width: -1, height: -1),
        CGSize(width: -1, height: 1),
        CGSize(width: 1, height: -1),
        CGSize(width: 1, height: 1)
    ]
}

private struct OverlayFlowAnimationState: Equatable {
    let captionEpoch: Int
    let translatedText: String
    let sourceText: String
    let committedPromotionID: UUID?
    let draftPromotionID: UUID?
    let reservesCommittedSlot: Bool
}

private struct OverlayHistoryLayoutAnimationState: Equatable {
    let historyIDs: [UUID]
    let reservesCommittedSlot: Bool
    let draftPromotionID: UUID?
}

private struct DraftSlotHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct LiveLayersHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct CommittedSlotHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct HistoryEntryHeightsPreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]

    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { _, new in new }
    }
}

private struct HistoryReviewContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0.0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct OverlayTranslationHostModifier: ViewModifier {
    @ObservedObject var model: AppModel

    func body(content: Content) -> some View {
        // Translation resource preparation can begin before the live session
        // flips to `.running`, so keep a host attached for the lifetime of the overlay view.
        content.hearSubTranslationHost(model: model)
    }
}

struct OverlayControlsChromeView: View {
    var body: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
            .frame(width: OverlayControlsLayout.stripSize.width, height: OverlayControlsLayout.stripSize.height)
    }
}

struct OverlayMoveButtonView: View {
    let onMoveDragStart: () -> Void
    let onMoveDragChanged: (CGSize) -> Void
    let onMoveDragEnded: () -> Void

    @State private var isMoveDragging = false

    var body: some View {
        OverlayDragHandle(
            onDragStart: {
                isMoveDragging = true
                onMoveDragStart()
            },
            onDragChanged: { translation in
                onMoveDragChanged(translation)
            },
            onDragEnded: {
                if isMoveDragging {
                    onMoveDragEnded()
                }
                isMoveDragging = false
            }
        )
        .frame(width: OverlayControlsLayout.controlSize, height: OverlayControlsLayout.controlSize)
        .background(Circle().fill(Color(nsColor: .controlColor).opacity(0.82)))
        .overlay(
            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundColor(Color(nsColor: .secondaryLabelColor))
                .allowsHitTesting(false)
        )
        .help("Drag")
    }
}

struct OverlayCloseButtonView: View {
    @ObservedObject var model: AppModel
    var onClose: () -> Void = {}

    var body: some View {
        Button { onClose() } label: {
            ZStack {
                Circle().fill(Color(red: 1.0, green: 0.36, blue: 0.32))
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Color(red: 0.44, green: 0.05, blue: 0.03).opacity(0.72))
            }
        }
        .buttonStyle(.plain)
        .frame(width: OverlayControlsLayout.controlSize, height: OverlayControlsLayout.controlSize)
        .help(model.localized(.hideOverlay))
    }
}

struct OverlayResizeButtonView: View {
    let onResizeDragStart: () -> Void
    let onResizeDragChanged: (CGSize) -> Void
    let onResizeDragEnded: () -> Void

    var body: some View {
        OverlayDragHandle(
            onDragStart: onResizeDragStart,
            onDragChanged: onResizeDragChanged,
            onDragEnded: onResizeDragEnded
        )
        .frame(width: OverlayControlsLayout.controlSize, height: OverlayControlsLayout.controlSize)
        .background(Circle().fill(Color.white.opacity(0.12)))
        .overlay(
            OverlayResizeGlyph()
                .frame(width: 10, height: 10)
                .allowsHitTesting(false)
        )
    }
}

struct OverlayResetSizeButtonView: View {
    @ObservedObject var model: AppModel
    let onReset: () -> Void

    var body: some View {
        Button { onReset() } label: {
            ZStack {
                Circle().fill(Color.white.opacity(0.12))
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.white.opacity(0.65))
            }
        }
        .buttonStyle(.plain)
        .frame(width: OverlayControlsLayout.controlSize, height: OverlayControlsLayout.controlSize)
        .accessibilityLabel(model.localized(.resetOverlaySize))
    }
}

struct OverlayHistoryScrollbarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var interactionState: OverlayInteractionState
    var showTranscript: () -> Void = {}

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = max(proxy.size.height - (OverlayHistoryScrollbarLayout.verticalPadding * 2), 1)
            let metrics = scrollbarMetrics(trackHeight: trackHeight)
            let opacity = metrics.canScroll ? 1.0 : 0.0

            ZStack(alignment: .top) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: OverlayHistoryScrollbarLayout.trackWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

                Capsule()
                    .fill(Color.white.opacity(0.64))
                    .frame(
                        width: OverlayHistoryScrollbarLayout.thumbWidth,
                        height: metrics.thumbHeight
                    )
                    .frame(maxWidth: .infinity, alignment: .top)
                    .offset(y: metrics.thumbTop)

                OverlayHistoryScrollbarInputLayer(
                    currentOffset: interactionState.historyScrollOffset,
                    maxScrollOffset: metrics.maxScrollOffset,
                    thumbHeight: metrics.thumbHeight,
                    onOffsetChange: { interactionState.setHistoryScrollOffset($0) },
                    onStepScroll: { interactionState.scrollHistory(by: $0) }
                )
            }
            .frame(height: trackHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .opacity(opacity)
            .allowsHitTesting(metrics.canScroll)
            .animation(.easeOut(duration: 0.14), value: metrics.canScroll)
            .transaction { transaction in
                transaction.animation = nil
            }
        }
    }

    private func scrollbarMetrics(trackHeight: CGFloat) -> OverlayHistoryScrollbarMetrics {
        let maxScrollOffset = max(interactionState.historyScrollMaxOffset, 0)
        let clampedTrackHeight = max(trackHeight, OverlayHistoryScrollbarLayout.minimumThumbHeight)
        let contentHeight = max(interactionState.historyScrollContentHeight, 0)
        let viewportHeight = max(interactionState.historyScrollViewportHeight, 0)
        let visibilityRatio = contentHeight > 0
            ? min(1.0, viewportHeight / max(contentHeight, viewportHeight))
            : 1.0
        let thumbHeight = max(
            OverlayHistoryScrollbarLayout.minimumThumbHeight,
            clampedTrackHeight * visibilityRatio
        )
        let travel = max(clampedTrackHeight - thumbHeight, 0)
        let progressFromTop: CGFloat

        if maxScrollOffset > 0 {
            progressFromTop = 1.0 - (interactionState.historyScrollOffset / maxScrollOffset)
        } else {
            progressFromTop = 1.0
        }

        return OverlayHistoryScrollbarMetrics(
            maxScrollOffset: maxScrollOffset,
            thumbHeight: min(thumbHeight, clampedTrackHeight),
            thumbTop: travel * progressFromTop,
            canScroll: maxScrollOffset > 0
        )
    }
}

enum OverlayControlsLayout {
    static let outerPadding: CGFloat = 6
    static let leadingInset: CGFloat = 10
    static let controlPaddingX: CGFloat = 8
    static let controlPaddingY: CGFloat = 6
    static let controlSize: CGFloat = 14
    static let controlSpacing: CGFloat = 8

    static let controlCount = 2

    static var stripSize: CGSize {
        let controlStackWidth = (controlSize * CGFloat(controlCount))
            + (controlSpacing * CGFloat(controlCount - 1))
        return CGSize(
            width: controlStackWidth + (controlPaddingX * 2),
            height: controlSize + (controlPaddingY * 2)
        )
    }

    /// Control panel chrome height (two macOS-style buttons + vertical padding inside the strip).
    static var controlPanelHeight: CGFloat {
        stripSize.height
    }

    /// Overlay must be at least this tall so the chrome strip (offset by `outerPadding` from the bottom) fits inside.
    static var minimumOverlayHeight: CGFloat {
        56
    }
}

enum OverlayHistoryScrollbarLayout {
    static let panelWidth: CGFloat = 28
    static let trackWidth: CGFloat = 5
    static let thumbWidth: CGFloat = 8
    static let expandedTrackWidth: CGFloat = 8
    static let contentSpacing: CGFloat = 10
    static let verticalPadding: CGFloat = 8
    static let buttonSpacing: CGFloat = 8
    static let minimumThumbHeight: CGFloat = 36

    static var panelSize: CGSize {
        CGSize(width: panelWidth, height: 120)
    }
}

private struct OverlayHistoryScrollbarMetrics {
    var maxScrollOffset: CGFloat
    var thumbHeight: CGFloat
    var thumbTop: CGFloat
    var canScroll: Bool
}

private struct OverlayHistoryScrollbarInputLayer: NSViewRepresentable {
    let currentOffset: CGFloat
    let maxScrollOffset: CGFloat
    let thumbHeight: CGFloat
    let onOffsetChange: (CGFloat) -> Void
    let onStepScroll: (CGFloat) -> Void

    func makeNSView(context: Context) -> OverlayHistoryScrollbarInputView {
        let view = OverlayHistoryScrollbarInputView()
        view.currentOffset = currentOffset
        view.maxScrollOffset = maxScrollOffset
        view.thumbHeight = thumbHeight
        view.onOffsetChange = onOffsetChange
        view.onStepScroll = onStepScroll
        return view
    }

    func updateNSView(_ nsView: OverlayHistoryScrollbarInputView, context: Context) {
        nsView.currentOffset = currentOffset
        nsView.maxScrollOffset = maxScrollOffset
        nsView.thumbHeight = thumbHeight
        nsView.onOffsetChange = onOffsetChange
        nsView.onStepScroll = onStepScroll
    }
}

final class OverlayHistoryScrollbarInputView: NSView {
    var currentOffset: CGFloat = 0
    var maxScrollOffset: CGFloat = 0
    var thumbHeight: CGFloat = OverlayHistoryScrollbarLayout.minimumThumbHeight
    var onOffsetChange: ((CGFloat) -> Void)?
    var onStepScroll: ((CGFloat) -> Void)?

    private var isDraggingThumb = false

    override var isFlipped: Bool { true }

    override func mouseDown(with event: NSEvent) {
        isDraggingThumb = true
        updateOffset(for: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard isDraggingThumb else { return }
        updateOffset(for: event)
    }

    override func mouseUp(with event: NSEvent) {
        if isDraggingThumb {
            updateOffset(for: event)
        }
        isDraggingThumb = false
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxScrollOffset > 0 else { return }

        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }

        let pixelDelta = event.hasPreciseScrollingDeltas ? delta : delta * 42
        onStepScroll?(pixelDelta)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func updateOffset(for event: NSEvent) {
        guard maxScrollOffset > 0 else {
            onOffsetChange?(0)
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        onOffsetChange?(resolvedOffset(forThumbCenterY: point.y))
    }

    private func resolvedOffset(forThumbCenterY thumbCenterY: CGFloat) -> CGFloat {
        let clampedThumbHeight = min(max(thumbHeight, 0), bounds.height)
        let travel = max(bounds.height - clampedThumbHeight, 0)
        guard travel > 0 else { return 0 }

        let thumbTop = min(max(thumbCenterY - (clampedThumbHeight / 2), 0), travel)
        let progressFromBottom = 1.0 - (thumbTop / travel)
        return progressFromBottom * maxScrollOffset
    }
}

private struct OverlayDragHandle: NSViewRepresentable {
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> OverlayDragHandleView {
        let view = OverlayDragHandleView()
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: OverlayDragHandleView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
    }
}

final class OverlayDragHandleView: NSView {
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?

    private var dragStartPointInScreen: NSPoint?

    override func mouseDown(with event: NSEvent) {
        guard let startPoint = screenPoint(for: event) else { return }
        dragStartPointInScreen = startPoint
        onDragStart?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPointInScreen,
              let currentPoint = screenPoint(for: event) else {
            return
        }

        onDragChanged?(
            CGSize(
                width: currentPoint.x - dragStartPointInScreen.x,
                height: currentPoint.y - dragStartPointInScreen.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        if dragStartPointInScreen != nil {
            onDragEnded?()
        }
        dragStartPointInScreen = nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        guard let window else { return nil }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}

private struct OverlayLongPressDragLayer: NSViewRepresentable {
    let onDragStart: () -> Void
    let onDragChanged: (CGSize) -> Void
    let onDragEnded: () -> Void
    let onHistoryScroll: (CGFloat) -> Void
    let onHistoryReset: () -> Void

    func makeNSView(context: Context) -> OverlayLongPressDragView {
        let view = OverlayLongPressDragView()
        view.onDragStart = onDragStart
        view.onDragChanged = onDragChanged
        view.onDragEnded = onDragEnded
        view.onHistoryScroll = onHistoryScroll
        view.onHistoryReset = onHistoryReset
        return view
    }

    func updateNSView(_ nsView: OverlayLongPressDragView, context: Context) {
        nsView.onDragStart = onDragStart
        nsView.onDragChanged = onDragChanged
        nsView.onDragEnded = onDragEnded
        nsView.onHistoryScroll = onHistoryScroll
        nsView.onHistoryReset = onHistoryReset
    }
}

final class OverlayLongPressDragView: NSView {
    var onDragStart: (() -> Void)?
    var onDragChanged: ((CGSize) -> Void)?
    var onDragEnded: (() -> Void)?
    var onHistoryScroll: ((CGFloat) -> Void)?
    var onHistoryReset: (() -> Void)?

    private var dragStartPointInScreen: NSPoint?
    private var hasActivatedDrag = false
    private var longPressTimer: Timer?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2 {
            onHistoryReset?()
            return
        }

        guard let startPoint = screenPoint(for: event) else { return }
        dragStartPointInScreen = startPoint
        hasActivatedDrag = false
        longPressTimer?.invalidate()

        let timer = Timer(timeInterval: Self.longPressDelay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.activateDragIfNeeded()
            }
        }
        longPressTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartPointInScreen,
              let currentPoint = screenPoint(for: event) else {
            return
        }

        guard hasActivatedDrag else { return }

        onDragChanged?(
            CGSize(
                width: currentPoint.x - dragStartPointInScreen.x,
                height: currentPoint.y - dragStartPointInScreen.y
            )
        )
    }

    override func mouseUp(with event: NSEvent) {
        longPressTimer?.invalidate()
        longPressTimer = nil

        if hasActivatedDrag {
            onDragEnded?()
        }

        dragStartPointInScreen = nil
        hasActivatedDrag = false
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY
        guard delta != 0 else { return }

        let pixelDelta = event.hasPreciseScrollingDeltas ? delta : delta * Self.lineScrollPixels
        onHistoryScroll?(pixelDelta)
    }

    override func mouseExited(with event: NSEvent) {
        guard hasActivatedDrag == false else { return }
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func activateDragIfNeeded() {
        guard dragStartPointInScreen != nil, hasActivatedDrag == false else { return }
        hasActivatedDrag = true
        onDragStart?()
    }

    private func screenPoint(for event: NSEvent) -> NSPoint? {
        guard let window else { return nil }
        return window.convertPoint(toScreen: event.locationInWindow)
    }

    private static let longPressDelay: TimeInterval = 0.28
    private static let lineScrollPixels: CGFloat = 42
}

private struct OverlayResizeGlyph: View {
    var body: some View {
        Canvas { context, size in
            let stroke = StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round)
            let color = Color.white.opacity(0.65)
            let start = CGPoint(x: 2, y: size.height - 2)
            let end = CGPoint(x: size.width - 2, y: 2)

            var diagonal = Path()
            diagonal.move(to: start)
            diagonal.addLine(to: end)
            context.stroke(diagonal, with: .color(color), style: stroke)

            var startHead = Path()
            startHead.move(to: start)
            startHead.addLine(to: CGPoint(x: start.x + 2.6, y: start.y))
            startHead.move(to: start)
            startHead.addLine(to: CGPoint(x: start.x, y: start.y - 2.6))
            context.stroke(startHead, with: .color(color), style: stroke)

            var endHead = Path()
            endHead.move(to: end)
            endHead.addLine(to: CGPoint(x: end.x - 2.6, y: end.y))
            endHead.move(to: end)
            endHead.addLine(to: CGPoint(x: end.x, y: end.y + 2.6))
            context.stroke(endHead, with: .color(color), style: stroke)
        }
    }
}

@MainActor
final class OverlayInteractionState: ObservableObject {
    @Published private(set) var passThroughBubble: OverlayPassThroughBubble?
    @Published private(set) var scrollbarRevealProgress: CGFloat = 0.0
    @Published private(set) var historyScrollOffset: CGFloat = 0.0
    @Published private(set) var historyScrollMaxOffset: CGFloat = 0.0
    @Published private(set) var historyScrollContentHeight: CGFloat = 0.0
    @Published private(set) var historyScrollViewportHeight: CGFloat = 0.0
    private var pendingHistoryScrollDelta: CGFloat = 0.0
    private var hasScheduledHistoryScrollFlush = false

    func updatePassThroughBubble(_ bubble: OverlayPassThroughBubble?) {
        guard needsUpdate(from: passThroughBubble, to: bubble) else { return }
        passThroughBubble = bubble
    }

    func updateScrollbarRevealProgress(_ progress: CGFloat) {
        let clampedProgress = min(max(progress, 0.0), 1.0)
        guard abs(scrollbarRevealProgress - clampedProgress) > 0.01 else { return }
        scrollbarRevealProgress = clampedProgress
    }

    func updateHistoryScrollMetrics(contentHeight: CGFloat, viewportHeight: CGFloat) {
        let normalizedContentHeight = max(contentHeight, 0)
        let normalizedViewportHeight = max(viewportHeight, 0)
        let maxOffset = max(normalizedContentHeight - normalizedViewportHeight, 0)

        var changed = false
        if abs(historyScrollContentHeight - normalizedContentHeight) > 0.5 {
            historyScrollContentHeight = normalizedContentHeight
            changed = true
        }
        if abs(historyScrollViewportHeight - normalizedViewportHeight) > 0.5 {
            historyScrollViewportHeight = normalizedViewportHeight
            changed = true
        }
        if abs(historyScrollMaxOffset - maxOffset) > 0.5 {
            historyScrollMaxOffset = maxOffset
            changed = true
        }

        let clampedOffset = min(max(historyScrollOffset, 0), maxOffset)
        if abs(historyScrollOffset - clampedOffset) > 0.5 || (maxOffset == 0 && historyScrollOffset != 0) {
            historyScrollOffset = clampedOffset
        } else if changed {
            objectWillChange.send()
        }
    }

    func scrollHistory(by delta: CGFloat) {
        guard delta != 0 else { return }
        pendingHistoryScrollDelta += delta

        guard hasScheduledHistoryScrollFlush == false else { return }
        hasScheduledHistoryScrollFlush = true

        Task { @MainActor [weak self] in
            await Task.yield()
            self?.flushPendingHistoryScrollDelta()
        }
    }

    func setHistoryScrollOffset(_ offset: CGFloat) {
        pendingHistoryScrollDelta = 0
        let clampedOffset = min(max(offset, 0), historyScrollMaxOffset)
        guard abs(historyScrollOffset - clampedOffset) > 0.25 else { return }
        withTransaction(Self.noAnimationTransaction) {
            historyScrollOffset = clampedOffset
        }
    }

    private func flushPendingHistoryScrollDelta() {
        hasScheduledHistoryScrollFlush = false
        let delta = pendingHistoryScrollDelta
        pendingHistoryScrollDelta = 0
        guard delta != 0 else { return }
        let clampedOffset = min(max(historyScrollOffset + delta, 0), historyScrollMaxOffset)
        guard abs(historyScrollOffset - clampedOffset) > 0.25 else { return }
        withTransaction(Self.noAnimationTransaction) {
            historyScrollOffset = clampedOffset
        }
    }

    private func needsUpdate(from current: OverlayPassThroughBubble?, to next: OverlayPassThroughBubble?) -> Bool {
        switch (current, next) {
        case (nil, nil):
            return false
        case (nil, _), (_, nil):
            return true
        case let (.some(current), .some(next)):
            return abs(current.center.x - next.center.x) > 0.5
                || abs(current.center.y - next.center.y) > 0.5
                || abs(current.diameter - next.diameter) > 0.5
        }
    }

    private static var noAnimationTransaction: Transaction {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        transaction.animation = nil
        return transaction
    }
}

struct OverlayPassThroughBubble: Equatable {
    var center: CGPoint
    var diameter: CGFloat
}

private struct OverlayPassThroughBubbleView: View {
    var body: some View {
        Circle()
            .fill(
                RadialGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .clear, location: 0.42),
                        .init(color: Color.black.opacity(0.12), location: 0.68),
                        .init(color: Color.black.opacity(0.07), location: 0.84),
                        .init(color: .clear, location: 1.0)
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: 58
                )
            )
            .blur(radius: 1.6)
    }
}

private extension OverlayView {
    static let passThroughTransitionDuration: Double = 0.18
    static let passThroughTransitionAnimation = Animation.easeOut(duration: passThroughTransitionDuration)
}
