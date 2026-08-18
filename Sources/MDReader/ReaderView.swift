import SwiftUI
import MarkdownUI

/// Marks the section a search hit landed in. Kept as its own object so that the
/// tiny per-section backdrops can observe it without the surrounding document
/// (and its table layouts) being invalidated.
@MainActor
final class FlashState: ObservableObject {
    @Published var id: String?
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

    /// Bound to ScrollView's actively-visible target via .scrollPosition.
    @State private var visibleSectionID: String?
    @State private var flash = FlashState()
    @State private var flashToken = 0

    var body: some View {
        ScrollView {
            SectionsStack(
                sections: document.sections,
                revision: document.revision,
                fontSize: settings.fontSize,
                flash: flash
            )
            .equatable()
        }
        .scrollPosition(id: $visibleSectionID, anchor: .top)
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
        .onChange(of: visibleSectionID) { _, newID in
            guard let newID else { return }
            document.lastSectionID = newID
            if newID != "__preamble__", newID != sectionState.current {
                sectionState.current = newID
            }
        }
        .onChange(of: scrollRequest) { _, request in
            guard let request else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                visibleSectionID = request.sectionID
            }
            if request.flash { startFlash(request.sectionID) }
        }
        .onAppear {
            // Restore where this tab was left; a fresh document starts at the top.
            let target = document.lastSectionID ?? document.sections.first?.id
            if let target, target != visibleSectionID {
                DispatchQueue.main.async { visibleSectionID = target }
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
        flash.id = id
        flashToken += 1
        let token = flashToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            if flashToken == token { flash.id = nil }
        }
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
private struct SectionsStack: View, Equatable {
    let sections: [MarkdownDocument.Section]
    let revision: Int
    let fontSize: Double
    let flash: FlashState

    private let topPadding: CGFloat = 48
    private let bottomPadding: CGFloat = 96
    private let horizontalPadding: CGFloat = 72
    private let maxContentWidth: CGFloat = 780

    nonisolated static func == (lhs: SectionsStack, rhs: SectionsStack) -> Bool {
        lhs.revision == rhs.revision
            && lhs.fontSize == rhs.fontSize
            && lhs.flash === rhs.flash
    }

    var body: some View {
        let theme = ThemeCache.reader(fontSize: fontSize)
        let firstID = sections.first?.id

        return VStack(alignment: .leading, spacing: 0) {
            ForEach(sections) { section in
                Markdown(section.markdown)
                    .markdownTheme(theme)
                    .textSelection(.enabled)
                    .background(FlashBackdrop(sectionID: section.id, state: flash))
                    .id(section.id)
                    .padding(.top, section.id == firstID ? 0 : sectionTopSpacing(for: section))
            }
        }
        .scrollTargetLayout()
        .frame(maxWidth: maxContentWidth, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .padding(.top, topPadding)
        .padding(.bottom, bottomPadding)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionTopSpacing(for section: MarkdownDocument.Section) -> CGFloat {
        guard let heading = section.heading else { return 12 }
        switch heading.level {
        case 1: return 48
        case 2: return 40
        case 3: return 28
        case 4: return 20
        case 5: return 16
        default: return 12
        }
    }
}

/// One rounded wash per section. Observing `FlashState` here — rather than in
/// `SectionsStack` — keeps a search jump from re-rendering the Markdown itself.
private struct FlashBackdrop: View {
    let sectionID: String
    @ObservedObject var state: FlashState

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color.accentColor.opacity(state.id == sectionID ? 0.12 : 0))
            .padding(.horizontal, -14)
            .padding(.vertical, -8)
            .animation(.easeOut(duration: 0.35), value: state.id == sectionID)
    }
}

private struct ScrollMetrics: Equatable {
    let offsetY: CGFloat
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
}
