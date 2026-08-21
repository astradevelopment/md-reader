import SwiftUI
import MarkdownUI

/// Browser-style tabs, living in the toolbar row itself — the tab *is* the title.
///
/// Deliberately without a capsule of its own: the toolbar already provides one
/// surface, so a container here would stack a second backdrop under the tabs and
/// a third under the selected one.
struct TabStrip: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var layout: ToolbarLayout
    let hover: TabHoverState

    private static let maxTabWidth: CGFloat = 240
    /// Below this a tab shows three letters and an ellipsis, which is no use to
    /// anyone. Rather than shrink them all past legibility, the ones that do not
    /// fit go to the menu — three readable tabs beat six illegible ones.
    private static let minTabWidth: CGFloat = 96
    private static let spacing: CGFloat = 3
    private static let buttonWidth: CGFloat = 24
    private static let menuWidth: CGFloat = 30

    /// Tabs are what gives way when the toolbar runs short: they narrow first —
    /// sharing what room there is between however many are open — and only then
    /// start collapsing into the overflow menu.
    private var tabWidth: CGFloat {
        let room = layout.availableForTabs - Self.buttonWidth - Self.spacing
        let share = room / CGFloat(max(1, store.documents.count))
        return min(Self.maxTabWidth, max(Self.minTabWidth, share - Self.spacing))
    }

    var body: some View {
        let split = split()

        return HStack(spacing: Self.spacing) {
            ForEach(split.visible) { document in
                TabPill(
                    id: document.id,
                    title: document.displayName,
                    fullName: document.fileName,
                    isSelected: document.id == store.selectedID,
                    showsClose: store.documents.count > 1,
                    fixedWidth: store.documents.count > 1 ? tabWidth : nil,
                    hover: hover,
                    // Enough to fill the little page rather than run out halfway
                    // down it — what does not fit is clipped and faded anyway.
                    opening: Array(document.blocks.prefix(14)),
                    onSelect: { store.select(document.id) },
                    onClose: { store.close(document.id) },
                    onDrop: { dragged in store.move(dragged, onto: document.id) }
                )
            }

            if !split.overflow.isEmpty {
                OverflowMenu(documents: split.overflow, selectedID: store.selectedID) { id in
                    store.select(id)
                }
            }

            OpenMenu(store: store)
        }
        // A ceiling, not a demand. A fixed width makes the item ask for exactly
        // this much and the controls then lose their place; a ceiling lets the
        // strip take only what its pills need, and `TabSplit.fitting` has already
        // chosen a number of pills that stays inside it.
        .frame(maxWidth: max(60, layout.availableForTabs), alignment: .leading)
        .animation(.snappy(duration: 0.2), value: store.documents.count)
    }

    private var visibleCount: Int {
        TabSplit.fitting(
            count: store.documents.count,
            available: layout.availableForTabs,
            tabWidth: tabWidth,
            spacing: Self.spacing,
            buttonWidth: Self.buttonWidth,
            menuWidth: Self.menuWidth
        )
    }

    private func split() -> (visible: [MarkdownDocument], overflow: [MarkdownDocument]) {
        let documents = store.documents
        let ids = TabSplit.split(
            ids: documents.map(\.id),
            selected: store.selectedID,
            visible: visibleCount
        )
        let visible = Set(ids.visible)
        return (
            documents.filter { visible.contains($0.id) },
            documents.filter { !visible.contains($0.id) }
        )
    }
}

/// The "+" button: opening a file, or picking one you had open recently, without
/// a trip to the File menu.
private struct OpenMenu: View {
    @ObservedObject var store: DocumentStore

    @State private var hovering = false

    /// Recents outlive the files themselves, so anything that moved is dropped.
    private var recents: [URL] {
        store.recentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        Menu {
            Button("Open…") { store.openPanel() }

            if !recents.isEmpty {
                Divider()
                ForEach(recents, id: \.self) { url in
                    Button {
                        store.open(url: url)
                    } label: {
                        Text(url.deletingPathExtension().lastPathComponent)
                    }
                }
                Divider()
                Button("Clear Menu") { store.clearRecent() }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: ToolbarMetrics.contentHeight, height: ToolbarMetrics.contentHeight)
                .contentShape(Circle())
                .background(
                    Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0))
                )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: ToolbarMetrics.contentHeight)
        .onHover { hovering = $0 }
        .help("Open a file (⌘O)")
    }
}

/// The tabs that did not fit, with a look inside each.
///
/// A popover rather than a `Menu`: menu items cannot report hover, and these are
/// exactly the documents whose names are cut hardest — the ones most in need of a
/// glance at their contents. The preview sits in the same popover, beside the
/// list, so it needs no window coordinates to place itself.
private struct OverflowMenu: View {
    let documents: [MarkdownDocument]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    @State private var hovering = false
    @State private var showing = false
    @State private var previewed: UUID?

    private let listWidth: CGFloat = 230
    private let previewWidth: CGFloat = 300
    private let previewHeight: CGFloat = 240

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            HStack(spacing: 1) {
                Text(verbatim: "\(documents.count)")
                    .font(.system(size: 10, design: .rounded).monospacedDigit())
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(.secondary)
            .frame(width: 30, height: ToolbarMetrics.contentHeight)
            .contentShape(Capsule())
            .background(
                Capsule().fill(Color.primary.opacity(hovering || showing ? 0.1 : 0))
            )
        }
        .buttonStyle(.plain)
        .frame(width: 30)
        .onHover { hovering = $0 }
        .help("\(documents.count) more open")
        .popover(isPresented: $showing, arrowEdge: .bottom) { panel }
        .onChange(of: showing) { _, isOpen in
            // Open on the document the pointer will most likely want: the one
            // already in front if it is in here, otherwise the first.
            if isOpen { previewed = selectedID.flatMap(idIfPresent) ?? documents.first?.id }
        }
    }

    private var panel: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(documents) { document in
                    row(document)
                }
            }
            .padding(6)
            .frame(width: listWidth, alignment: .leading)

            if let document = documents.first(where: { $0.id == previewed }),
               !document.blocks.isEmpty {
                Divider()
                TabPreviewPage(
                    blocks: Array(document.blocks.prefix(14)),
                    width: previewWidth,
                    height: previewHeight
                )
                .padding(8)
            }
        }
        .frame(height: previewHeight + 16)
    }

    private func row(_ document: MarkdownDocument) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .semibold))
                .opacity(document.id == selectedID ? 1 : 0)
            Text(document.fileName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(previewed == document.id ? 0.08 : 0))
        )
        .onHover { inside in
            if inside { previewed = document.id }
        }
        .onTapGesture {
            onSelect(document.id)
            showing = false
        }
    }

    private func idIfPresent(_ id: UUID) -> UUID? {
        documents.contains { $0.id == id } ? id : nil
    }
}

private struct TabPill: View {
    let id: UUID
    let title: String
    let fullName: String
    let isSelected: Bool
    let showsClose: Bool
    let fixedWidth: CGFloat?
    let hover: TabHoverState
    let opening: [MarkdownDocument.Block]
    let onSelect: () -> Void
    let onClose: () -> Void
    let onDrop: (UUID) -> Void

    @State private var hovering = false
    @State private var closeHovering = false
    @State private var isDropTarget = false
    @State private var frame: CGRect = .zero

    /// Room kept on both sides so the title is centred against the whole tab, not
    /// against whatever the close button leaves over.
    private var sideInset: CGFloat { showsClose ? 22 : 10 }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, sideInset)

            if showsClose {
                HStack(spacing: 0) {
                    // Leading edge, the way macOS puts it.
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                        .background(
                            Circle().fill(Color.primary.opacity(closeHovering ? 0.16 : 0))
                        )
                        .contentShape(Circle())
                        // Safari's behaviour: the cross belongs to the tab under
                        // the pointer, not to the one you are reading. Its space
                        // is reserved either way, so nothing shifts as it appears.
                        .opacity(hovering ? 1 : 0)
                        .onHover { closeHovering = $0 }
                        .onTapGesture(perform: onClose)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 5)
            }
        }
        .frame(height: ToolbarMetrics.contentHeight)
        .frame(width: fixedWidth)
        .frame(minWidth: fixedWidth == nil ? 60 : nil, maxWidth: fixedWidth == nil ? 220 : nil)
        .background(
            Capsule().fill(Color.primary.opacity(fillOpacity))
        )
        .contentShape(Capsule())
        .overlay(alignment: .leading) {
            if isDropTarget {
                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: 2)
                    .padding(.vertical, 2)
            }
        }
        // The identifier travels as text; anything else dropped here is ignored.
        .draggable(id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let dragged = items.first.flatMap(UUID.init(uuidString:)) else { return false }
            onDrop(dragged)
            return true
        } isTargeted: { isDropTarget = $0 }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { isInside in
            hovering = isInside
            if isInside {
                hover.enter(id: id, name: fullName, anchor: frame, opening: opening)
            } else {
                hover.leave(id: id)
            }
        }
        .onTapGesture(perform: onSelect)
    }

    private var fillOpacity: Double {
        // Solid enough that the title reads clearly against the toolbar's glass.
        if isSelected { return 0.17 }
        return hovering ? 0.06 : 0
    }
}

/// A glance at the document under the pointer: its name, and the first of it
/// rendered small.
///
/// A sibling of the document rather than an overlay on it, so hovering a tab
/// never invalidates the reader. Positioned from the window coordinates the tab
/// reports — toolbar items and content share that space.
struct TabTooltipLayer: View {
    @ObservedObject var hover: TabHoverState

    private let cardWidth: CGFloat = 400
    private let previewHeight: CGFloat = 290
    /// The margins of the little page, so it reads as a document rather than as
    /// text pressed against a box.
    private let pageInset: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            if let info = hover.info {
                card(for: info)
                    .frame(width: cardWidth)
                    // Offset from the top-left rather than positioned by centre:
                    // the gap under the tab is then exact, instead of depending on
                    // a guess at how tall the card turned out.
                    .offset(x: cardX(info: info, in: geo), y: gapBelowTab)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: hover.info)
    }

    private func card(for info: TabHoverState.Info) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(info.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 2)

            if !info.opening.isEmpty {
                TabPreviewPage(blocks: info.opening, width: cardWidth - 24, height: previewHeight)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    private var gapBelowTab: CGFloat { 4 }

    /// Centred under the tab, nudged inwards so it never runs off either edge.
    private func cardX(info: TabHoverState.Info, in geo: GeometryProxy) -> CGFloat {
        let centre = info.anchor.midX - geo.frame(in: .global).minX
        let leading = centre - cardWidth / 2
        let limit = max(8, geo.size.width - cardWidth - 8)
        return min(max(leading, 8), limit)
    }
}

/// The opening of a document, small enough that a screenful fits, cut off at the
/// bottom with a fade rather than a hard edge.
///
/// Shared by the tab tooltip and the overflow menu: a tab that no longer fits on
/// the strip is exactly the one whose name is cut hardest, so a glance at what is
/// inside it is worth more there, not less.
struct TabPreviewPage: View {
    let blocks: [MarkdownDocument.Block]
    let width: CGFloat
    let height: CGFloat

    /// The margins of the little page, so it reads as a document rather than as
    /// text pressed against a box.
    private let pageInset: CGFloat = 16

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(blocks) { block in
                Markdown(block.markdown)
                    .markdownTheme(ThemeCache.reader(fontSize: 8))
            }
        }
        .padding(pageInset)
        .frame(width: width, alignment: .leading)
        .frame(height: height, alignment: .top)
        .clipped()
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.78),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        // Applied after the mask, so the page keeps its shape while the text
        // fades off the bottom of it.
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }
}
