import SwiftUI

/// Browser-style tabs, living in the toolbar row itself — the tab *is* the title.
struct TabStrip: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 2) {
            ForEach(store.documents) { document in
                TabPill(
                    title: document.fileName,
                    isSelected: document.id == store.selectedID,
                    showsClose: store.documents.count > 1,
                    onSelect: { store.select(document.id) },
                    onClose: { store.close(document.id) }
                )
            }

            CapsuleIconButton(systemName: "plus", help: "Open a file (⌘O)") {
                store.openPanel()
            }
        }
        .toolbarCluster()
        .animation(.snappy(duration: 0.2), value: store.documents.count)
    }
}

private struct TabPill: View {
    let title: String
    let isSelected: Bool
    let showsClose: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)

            if showsClose {
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
        }
        .padding(.leading, 10)
        .padding(.trailing, showsClose ? 4 : 10)
        .frame(height: ToolbarMetrics.contentHeight)
        .frame(minWidth: 64, maxWidth: 170)
        .background(
            Capsule().fill(Color.primary.opacity(fillOpacity))
        )
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .help(title)
    }

    private var fillOpacity: Double {
        if isSelected { return 0.12 }
        return hovering ? 0.06 : 0
    }
}
