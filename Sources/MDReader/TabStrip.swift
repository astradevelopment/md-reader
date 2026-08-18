import SwiftUI

/// Browser-style tab bar across the top of the document pane.
struct TabStrip: View {
    @ObservedObject var store: DocumentStore

    var body: some View {
        HStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(store.documents) { document in
                            TabItem(
                                title: document.fileName,
                                isSelected: document.id == store.selectedID,
                                onSelect: { store.select(document.id) },
                                onClose: { store.close(document.id) }
                            )
                            .id(document.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .onChange(of: store.selectedID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }

            Button {
                store.openPanel()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .frame(width: 24, height: 24)
                    .contentShape(Circle())
            }
            .buttonStyle(HoverCircleButtonStyle())
            .padding(.trailing, 8)
            .help("Open a file (⌘O)")
        }
        .frame(height: 36)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.dividerSoft)
        }
    }
}

private struct TabItem: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void

    @State private var hovering = false
    @State private var closeHovering = false

    var body: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)

            // Only the active or hovered tab offers a close button, so a crowded
            // strip stays readable.
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 15, height: 15)
                .background(
                    Circle().fill(Color.primary.opacity(closeHovering ? 0.14 : 0))
                )
                .contentShape(Circle())
                .opacity(hovering || isSelected ? 1 : 0)
                .onHover { closeHovering = $0 }
                .onTapGesture(perform: onClose)
        }
        .padding(.leading, 11)
        .padding(.trailing, 6)
        .frame(height: 26)
        .frame(minWidth: 90, maxWidth: 190)
        .background(background)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
        .help(title)
    }

    @ViewBuilder
    private var background: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        }
    }
}

/// A plain button that grows a round hover halo — matches the toolbar controls.
struct HoverCircleButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.secondary)
            .background(
                Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0))
            )
            .opacity(configuration.isPressed ? 0.5 : 1)
            .onHover { hovering = $0 }
    }
}
