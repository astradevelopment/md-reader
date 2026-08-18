import SwiftUI

// MARK: - Glass

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
}

/// A borderless icon button sized for the toolbar capsules.
private struct CapsuleIconButton: View {
    let systemName: String
    var help: String = ""
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .background(
                    Circle()
                        .fill(Color.primary.opacity(hovering && enabled ? 0.1 : 0))
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

    var body: some View {
        HStack(spacing: 1) {
            CapsuleIconButton(
                systemName: "textformat.size.smaller",
                help: "Smaller text (⌘−)",
                enabled: settings.canDecrease
            ) { settings.decrease() }

            Divider()
                .frame(height: 12)
                .opacity(0.4)

            CapsuleIconButton(
                systemName: "textformat.size.larger",
                help: "Larger text (⌘+)",
                enabled: settings.canIncrease
            ) { settings.increase() }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 3)
        .glassCapsule(interactive: true)
        .contextMenu {
            Button("Actual Size (\(Int(ReaderSettings.defaultSize)) pt)") { settings.reset() }
        }
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
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(search.isPresented ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                .frame(width: 24, height: 24)
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
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .glassCapsule(interactive: true)
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
                .font(.system(.caption, design: .rounded).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)
        }
        .frame(width: 138, height: 24)
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .glassCapsule()
    }
}
