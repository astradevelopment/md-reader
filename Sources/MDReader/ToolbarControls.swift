import SwiftUI

// MARK: - Shared shape language

/// One set of numbers for every toolbar cluster, so tabs, search, text size and
/// progress read as the same control.
enum ToolbarMetrics {
    static let contentHeight: CGFloat = 24
    static let paddingH: CGFloat = 4
    static let paddingV: CGFloat = 3
}

extension View {
    /// Liquid Glass on macOS 26, a material capsule everywhere else.
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular.interactive(interactive), in: .capsule)
        } else {
            self.background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                )
        }
    }

    /// Wraps a cluster of controls in the standard glass capsule.
    func toolbarCluster(interactive: Bool = true) -> some View {
        self
            .frame(height: ToolbarMetrics.contentHeight)
            .padding(.horizontal, ToolbarMetrics.paddingH)
            .padding(.vertical, ToolbarMetrics.paddingV)
            .glassCapsule(interactive: interactive)
    }
}

/// A borderless icon button with a round hover halo.
struct CapsuleIconButton: View {
    let systemName: String
    /// LocalizedStringKey, not String: `.help(String)` would skip the lookup.
    var help: LocalizedStringKey = ""
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11, weight: .medium))
                .frame(width: ToolbarMetrics.contentHeight, height: ToolbarMetrics.contentHeight)
                .contentShape(Circle())
                .background(
                    Circle().fill(Color.primary.opacity(hovering && enabled ? 0.1 : 0))
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .onHover { hovering = $0 }
        .help(help)
    }
}

// MARK: - Text size

struct FontSizeControl: View {
    @ObservedObject var settings: ReaderSettings

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 0) {
            CapsuleIconButton(
                systemName: "textformat.size.smaller",
                help: "Smaller text (⌘−)",
                enabled: settings.canDecrease
            ) { settings.decrease() }

            percentField

            CapsuleIconButton(
                systemName: "textformat.size.larger",
                help: "Larger text (⌘+)",
                enabled: settings.canIncrease
            ) { settings.increase() }
        }
        .toolbarCluster()
        .contextMenu {
            Button("Actual Size (100%)") { settings.reset() }
        }
    }

    /// Always a live field with a fixed "%" beside it — never a label that swaps
    /// into an editor. A toolbar text field does not reliably report losing focus,
    /// so a mode switch would strand the control in its editing state.
    private var percentField: some View {
        HStack(spacing: 0) {
            TextField(
                "",
                value: $settings.percent,
                format: .number.precision(.fractionLength(0))
            )
            .textFieldStyle(.plain)
            .multilineTextAlignment(.trailing)
            .font(.system(size: 11, design: .rounded).monospacedDigit())
            .foregroundStyle(.primary)
            .frame(width: 26)
            .focused($focused)
            .onSubmit { focused = false }

            Text(verbatim: "%")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 5)
        .frame(height: ToolbarMetrics.contentHeight)
        .background(
            Capsule().fill(Color.primary.opacity(hovering || focused ? 0.1 : 0))
        )
        .contentShape(Capsule())
        .onHover { hovering = $0 }
        .onTapGesture { focused = true }
        .help("Type a size, or use ⌘+ / ⌘−")
    }
}

// MARK: - Search

struct SearchBar: View {
    @ObservedObject var search: SearchModel
    /// Called whenever the reader should scroll to `search.current`.
    var onJump: () -> Void

    @FocusState private var focused: Bool
    @State private var magnifierHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(search.isPresented ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: ToolbarMetrics.contentHeight, height: ToolbarMetrics.contentHeight)
                .contentShape(Circle())
                .background(
                    Circle().fill(Color.primary.opacity(magnifierHovering && !search.isPresented ? 0.1 : 0))
                )
                .onHover { magnifierHovering = $0 }
                .onTapGesture { open() }

            if search.isPresented {
                TextField("Find in document", text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .frame(width: 120)
                    .focused($focused)
                    .onSubmit { step(forward: true) }

                if search.hasQuery {
                    Text(verbatim: counterText)
                        .font(.system(size: 11, design: .rounded).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 40, alignment: .trailing)

                    CapsuleIconButton(
                        systemName: "chevron.up",
                        help: "Previous match (⇧⌘G)",
                        enabled: !search.matches.isEmpty
                    ) { step(forward: false) }

                    CapsuleIconButton(
                        systemName: "chevron.down",
                        help: "Next match (⌘G)",
                        enabled: !search.matches.isEmpty
                    ) { step(forward: true) }
                }

                CapsuleIconButton(systemName: "xmark", help: "Close (esc)") { close() }
            }
        }
        .toolbarCluster()
        .onExitCommand { close() }
        .onChange(of: search.isPresented) { _, presented in
            if presented {
                // The field only exists after this layout pass.
                DispatchQueue.main.async { focused = true }
            } else {
                focused = false
            }
        }
        .onChange(of: search.matches) { _, new in
            if !new.isEmpty { onJump() }
        }
        .animation(.snappy(duration: 0.22), value: search.isPresented)
        .animation(.snappy(duration: 0.22), value: search.hasQuery)
    }

    private var counterText: String {
        if search.matches.isEmpty { return String(localized: "no results") }
        let suffix = search.didHitLimit ? "+" : ""
        return "\(search.currentIndex + 1)/\(search.matches.count)\(suffix)"
    }

    private func open() {
        if search.isPresented {
            focused = true
        } else {
            search.isPresented = true
        }
    }

    private func close() {
        guard search.isPresented else { return }
        search.dismiss()
    }

    private func step(forward: Bool) {
        _ = forward ? search.next() : search.previous()
        onJump()
    }
}
