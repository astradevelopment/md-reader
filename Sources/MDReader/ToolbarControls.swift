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
    var help: String = ""
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

    @State private var editing = false
    @State private var draft = ""
    @State private var percentHovering = false
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

    @ViewBuilder
    private var percentField: some View {
        if editing {
            TextField("", text: $draft)
                .textFieldStyle(.plain)
                .multilineTextAlignment(.center)
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .frame(width: 42)
                .focused($focused)
                .onSubmit(commit)
                .onExitCommand { editing = false }
                .onChange(of: focused) { _, isFocused in
                    // Clicking away is a commit, the same as pressing return.
                    if !isFocused, editing { commit() }
                }
        } else {
            Text("\(Int(settings.percent))%")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 42, height: ToolbarMetrics.contentHeight)
                .background(
                    Capsule().fill(Color.primary.opacity(percentHovering ? 0.1 : 0))
                )
                .contentShape(Capsule())
                .onHover { percentHovering = $0 }
                .onTapGesture(perform: beginEditing)
                .help("Click to type a size")
        }
    }

    private func beginEditing() {
        draft = String(Int(settings.percent))
        editing = true
        DispatchQueue.main.async { focused = true }
    }

    private func commit() {
        settings.apply(typed: draft)
        editing = false
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
                    .frame(width: 150)
                    .focused($focused)
                    .onSubmit { step(forward: true) }

                if search.hasQuery {
                    Text(counterText)
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
        if search.matches.isEmpty { return "no results" }
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

// MARK: - Progress

struct ProgressPill: View {
    @ObservedObject var state: ProgressState

    var body: some View {
        HStack(spacing: 9) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.18))
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(2, geo.size.width * state.value))
                }
            }
            .frame(height: 4)

            Text("\(Int(state.value * 100))%")
                .font(.system(size: 11, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(width: 132)
        .padding(.horizontal, 8)
        .toolbarCluster(interactive: false)
    }
}
