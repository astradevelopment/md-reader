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
    private static let minTabWidth: CGFloat = 110
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
                    // Enough of the document to recognise it by, no more.
                    opening: Array(document.blocks.prefix(5)),
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
        // A hard ceiling, not just an arithmetic one. If the strip's intrinsic
        // width ever exceeded what the toolbar has left, the toolbar would take
        // the whole item into its own overflow popover — tab pills rendered
        // inside a system menu — instead of letting them collapse into the
        // chevron of their own.
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

private struct OverflowMenu: View {
    let documents: [MarkdownDocument]
    let selectedID: UUID?
    let onSelect: (UUID) -> Void

    @State private var hovering = false

    var body: some View {
        Menu {
            ForEach(documents) { document in
                Button {
                    onSelect(document.id)
                } label: {
                    if document.id == selectedID {
                        Label(document.fileName, systemImage: "checkmark")
                    } else {
                        Text(document.fileName)
                    }
                }
            }
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
                Capsule().fill(Color.primary.opacity(hovering ? 0.1 : 0))
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .onHover { hovering = $0 }
        .help("\(documents.count) more open")
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

    private let cardWidth: CGFloat = 300
    private let previewHeight: CGFloat = 168

    var body: some View {
        GeometryReader { geo in
            if let info = hover.info {
                card(for: info)
                    .frame(width: cardWidth)
                    .position(
                        x: anchorX(info: info, in: geo),
                        y: cardHeight(for: info) / 2 + 10
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: hover.info)
    }

    private func card(for info: TabHoverState.Info) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(info.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !info.opening.isEmpty {
                preview(info.opening)
            }
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
    }

    /// The document at a size where a screenful fits in a card, cut off at the
    /// bottom with a fade rather than a hard edge.
    private func preview(_ blocks: [MarkdownDocument.Block]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(blocks) { block in
                Markdown(block.markdown)
                    .markdownTheme(ThemeCache.reader(fontSize: 7))
            }
        }
        .frame(width: cardWidth - 20, alignment: .leading)
        .frame(height: previewHeight, alignment: .top)
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
        .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func cardHeight(for info: TabHoverState.Info) -> CGFloat {
        info.opening.isEmpty ? 36 : previewHeight + 50
    }

    /// Centred under the tab, nudged inwards so it never runs off either edge.
    private func anchorX(info: TabHoverState.Info, in geo: GeometryProxy) -> CGFloat {
        let local = info.anchor.midX - geo.frame(in: .global).minX
        let margin = cardWidth / 2 + 8
        return min(max(local, margin), max(margin, geo.size.width - margin))
    }
}
