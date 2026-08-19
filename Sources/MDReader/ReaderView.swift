import SwiftUI
import MarkdownUI

/// Marks the section a search hit landed in. Kept as its own object so that the
/// tiny per-section backdrops can observe it without the surrounding document
/// (and its table layouts) being invalidated.
@MainActor
final class FlashState: ObservableObject {
    /// Carries a token as well as the section, so that stepping between two
    /// matches inside the *same* section still registers as a new event. Without
    /// it the published value never changed, and the document sat there looking
    /// as though the arrows did nothing at all.
    struct Pulse: Equatable {
        let id: String
        let token: Int
    }

    @Published var pulse: Pulse?
}

struct ReaderView: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var settings: ReaderSettings

    /// Written to, never observed here — see `ProgressState` / `SectionState`.
    let progressState: ProgressState
    let sectionState: SectionState

    @Binding var scrollRequest: ScrollRequest?
    /// Dropping a file opens a tab rather than replacing this document.
    var onOpenFile: (URL) -> Void

    /// Bound to ScrollView's actively-visible target via .scrollPosition. A block
    /// now, not a section — that is what makes a hit land on one paragraph.
    @State private var visibleBlockID: String?
    @State private var flash = FlashState()
    @State private var flashToken = 0
    /// Raised while a jump is in flight, so the sidebar highlight does not race
    /// through every heading the scroll passes on the way.
    @State private var isJumping = false
    @State private var jumpToken = 0

    var body: some View {
        ScrollView {
            BlocksStack(
                blocks: document.blocks,
                revision: document.revision,
                fontSize: settings.fontSize,
                flash: flash
            )
            .equatable()
        }
        .scrollPosition(id: $visibleBlockID, anchor: .top)
        .onScrollGeometryChange(for: ScrollMetrics.self) { geo in
            ScrollMetrics(
                offsetY: geo.contentOffset.y,
                contentHeight: geo.contentSize.height,
                viewportHeight: geo.containerSize.height
            )
        } action: { _, new in
            let maxScroll = max(1, new.contentHeight - new.viewportHeight)
            let p = min(1, max(0, new.offsetY / maxScroll))
            // Only the toolbar pill observes this, so the document is untouched.
            if abs(p - progressState.value) > 0.002 { progressState.value = p }
            document.lastProgress = p
        }
        .onChange(of: visibleBlockID) { _, newID in
            guard let newID else { return }
            document.lastBlockID = newID
            guard !isJumping else { return }
            // The outline still tracks headings, so a block reports its section.
            guard let section = document.sectionOfBlock[newID] else { return }
            if section != "__preamble__", section != sectionState.current {
                sectionState.current = section
            }
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            // No animation: the document is rendered lazily, so animating a long
            // jump would realise — and scroll through — everything in between.
            isJumping = true
            jumpToken += 1
            let token = jumpToken
            visibleBlockID = request.targetID
            if request.flash { startFlash(request.targetID) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if jumpToken == token { isJumping = false }
            }
        }
        .onAppear {
            // Restore where this tab was left; a fresh document starts at the top.
            let target = document.lastBlockID ?? document.blocks.first?.id
            if let target, target != visibleBlockID {
                DispatchQueue.main.async { visibleBlockID = target }
            }
            if sectionState.current == nil, let first = document.headings.first?.id {
                sectionState.current = first
            }
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private func startFlash(_ id: String) {
        flashToken += 1
        flash.pulse = FlashState.Pulse(id: id, token: flashToken)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url = url else { return }
            DispatchQueue.main.async { onOpenFile(url) }
        }
        return true
    }
}

/// The rendered document.
///
/// `Equatable` is the point of this type: re-laying out a long document (tables in
/// particular) costs tens of milliseconds, and without it every scroll-driven state
/// change — the visible-section tracker, a search flash — would redo that work. Only
/// a new document or a new text size can invalidate it.
private struct BlocksStack: View, Equatable {
    let blocks: [MarkdownDocument.Block]
    let revision: Int
    let fontSize: Double
    let flash: FlashState

    private let topPadding: CGFloat = 48
    private let bottomPadding: CGFloat = 96
    private let horizontalPadding: CGFloat = 72
    private let maxContentWidth: CGFloat = 780

    nonisolated static func == (lhs: BlocksStack, rhs: BlocksStack) -> Bool {
        lhs.revision == rhs.revision
            && lhs.fontSize == rhs.fontSize
            && lhs.flash === rhs.flash
    }

    var body: some View {
        let theme = ThemeCache.reader(fontSize: fontSize)
        let firstID = blocks.first?.id

        return LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                Markdown(block.markdown)
                    .markdownTheme(theme)
                    .background(FlashBackdrop(blockID: block.id, state: flash))
                    .id(block.id)
                    .padding(
                        .top,
                        block.id == firstID
                            ? 0
                            : spacing(above: block, after: index > 0 ? blocks[index - 1] : nil)
                    )
            }
        }
        // On the stack rather than on each block: a selection cannot cross from
        // one view into another, so the fewer selection roots there are, the more
        // of the document a drag can take in.
        .textSelection(.enabled)
        .scrollTargetLayout()
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Rendering each block on its own means MarkdownUI no longer puts anything
    /// between them, so the theme's own margins are reproduced here. Measured
    /// against the previous rendering: twenty paragraphs came to 828 pt with the
    /// section rendered whole and 524 pt broken into blocks — 304 pt lost across
    /// nineteen gaps, exactly the 16 pt the theme gives a paragraph.
    private func spacing(above block: MarkdownDocument.Block,
                         after previous: MarkdownDocument.Block?) -> CGFloat {
        if let level = block.headingLevel { return aboveHeading(level) }
        if previous?.isThematicBreak == true { return ruleGap }
        if block.isThematicBreak { return ruleGap }
        if let level = previous?.headingLevel { return belowHeading(level) }
        return paragraphGap
    }

    private var paragraphGap: CGFloat { 16 }
    private var ruleGap: CGFloat { 24 }

    /// The air above a section, which is the theme's top margin for its heading.
    private func aboveHeading(_ level: Int) -> CGFloat {
        switch level {
        case 1: return 48
        case 2: return 40
        case 3: return 28
        case 4: return 20
        case 5: return 16
        default: return 12
        }
    }

    /// And the gap the theme leaves under one, before the text it introduces.
    private func belowHeading(_ level: Int) -> CGFloat {
        switch level {
        case 1, 2: return 12
        case 3: return 10
        case 4: return 8
        case 5: return 6
        default: return 4
        }
    }
}

/// One rounded wash per block. Observing `FlashState` here — rather than in
/// `SectionsStack` — keeps a search jump from re-rendering the Markdown itself.
private struct FlashBackdrop: View {
    let blockID: String
    @ObservedObject var state: FlashState

    /// Struck on arrival and then left to fade, so every press of the arrows
    /// reads as a fresh hit rather than a wash that was already there.
    @State private var intensity: Double = 0

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(intensity))
            .padding(.horizontal, -14)
            .padding(.vertical, -8)
            .onChange(of: state.pulse) { _, pulse in
                guard pulse?.id == blockID else {
                    if intensity != 0 {
                        withAnimation(.easeOut(duration: 0.2)) { intensity = 0 }
                    }
                    return
                }
                intensity = 0.20
                withAnimation(.easeOut(duration: 1.2)) { intensity = 0 }
            }
    }
}

private struct ScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}
