import SwiftUI

/// Browser-style tabs, living in the toolbar row itself — the tab *is* the title.
///
/// Deliberately without a capsule of its own: the toolbar already provides one
/// surface, so a container here would stack a second backdrop under the tabs and
/// a third under the selected one.
struct TabStrip: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject var layout: ToolbarLayout
    let hover: TabHoverState

    private static let tabWidth: CGFloat = 150
    private static let spacing: CGFloat = 3
    private static let buttonWidth: CGFloat = 24

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
                    fixedWidth: store.documents.count > 1 ? Self.tabWidth : nil,
                    hover: hover,
                    onSelect: { store.select(document.id) },
                    onClose: { store.close(document.id) }
                )
            }

            if !split.overflow.isEmpty {
                OverflowMenu(documents: split.overflow, selectedID: store.selectedID) { id in
                    store.select(id)
                }
            }

            CapsuleIconButton(systemName: "plus", help: "Open a file (⌘O)") {
                store.openPanel()
            }
        }
        .animation(.snappy(duration: 0.2), value: store.documents.count)
    }

    private var capacity: Int {
        TabSplit.capacity(
            available: layout.availableForTabs,
            tabWidth: Self.tabWidth,
            spacing: Self.spacing,
            buttonWidth: Self.buttonWidth
        )
    }

    private func split() -> (visible: [MarkdownDocument], overflow: [MarkdownDocument]) {
        let documents = store.documents
        let ids = TabSplit.split(
            ids: documents.map(\.id),
            selected: store.selectedID,
            capacity: capacity
        )
        let visible = Set(ids.visible)
        return (
            documents.filter { visible.contains($0.id) },
            documents.filter { !visible.contains($0.id) }
        )
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
                Text("\(documents.count)")
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
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false
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
                    Spacer(minLength: 0)

                    // Only the active or hovered tab offers a close button, so a
                    // crowded strip stays readable.
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 15, height: 15)
                        .background(
                            Circle().fill(Color.primary.opacity(closeHovering ? 0.16 : 0))
                        )
                        .contentShape(Circle())
                        .opacity(hovering || isSelected ? 1 : 0)
                        .onHover { closeHovering = $0 }
                        .onTapGesture(perform: onClose)
                }
                .padding(.trailing, 5)
            }
        }
        .frame(height: ToolbarMetrics.contentHeight)
        .frame(width: fixedWidth)
        .frame(minWidth: fixedWidth == nil ? 60 : nil, maxWidth: fixedWidth == nil ? 220 : nil)
        .background(
            Capsule().fill(Color.primary.opacity(fillOpacity))
        )
        .contentShape(Capsule())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onHover { isInside in
            hovering = isInside
            if isInside {
                hover.enter(id: id, name: fullName, anchor: frame)
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

/// The full filename, shown the instant the pointer lands on a tab.
///
/// A sibling of the document rather than an overlay on it, so hovering a tab
/// never invalidates the reader. Positioned from the window coordinates the tab
/// reports — toolbar items and content share that space.
struct TabTooltipLayer: View {
    @ObservedObject var hover: TabHoverState

    var body: some View {
        GeometryReader { geo in
            if let info = hover.info {
                Text(info.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
                    .shadow(color: .black.opacity(0.16), radius: 6, y: 2)
                    .fixedSize()
                    .position(
                        x: anchorX(info: info, in: geo),
                        y: 20
                    )
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: hover.info)
    }

    /// Centred under the tab, nudged inwards so it never runs off either edge.
    private func anchorX(info: TabHoverState.Info, in geo: GeometryProxy) -> CGFloat {
        let local = info.anchor.midX - geo.frame(in: .global).minX
        return min(max(local, 110), max(110, geo.size.width - 110))
    }
}
