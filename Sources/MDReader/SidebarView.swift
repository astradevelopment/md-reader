import SwiftUI

struct SidebarView: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var sectionState: SectionState
    /// Passed through unobserved — only the bar itself watches it, so a scroll
    /// does not redraw the whole outline.
    let progressState: ProgressState
    @ObservedObject var search: SearchModel

    var onSelectHeading: (String) -> Void
    var onSelectMatch: (Int) -> Void

    @State private var skipAutoScroll = false

    private var showingResults: Bool { search.isPresented && search.hasQuery }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if showingResults {
                results
            } else {
                contents
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SidebarBackdrop())
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // Verbatim: the text is already localised, and `Text(String)` would
            // not look it up a second time anyway.
            Text(verbatim: headerTitle)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
                .fixedSize()

            if hasDocument, !showingResults {
                ProgressReadout(state: progressState)
            }

            if hasDocument {
                ReadingProgressBar(state: progressState)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var hasDocument: Bool { !document.content.isEmpty }

    private var headerTitle: String {
        guard showingResults else { return String(localized: "CONTENTS") }
        if search.matches.isEmpty { return String(localized: "NO RESULTS") }
        let suffix = search.didHitLimit ? "+" : ""
        return String(localized: "RESULTS · \(search.matches.count)") + suffix
    }

    // MARK: - Table of contents

    @ViewBuilder
    private var contents: some View {
        if document.headings.isEmpty {
            placeholder(
                document.content.isEmpty
                    ? String(localized: "No file open")
                    : String(localized: "No headings found")
            )
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(document.headings) { h in
                            HeadingRow(heading: h, isSelected: sectionState.current == h.id)
                                .id(h.id)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    // The row is already under the pointer; scrolling
                                    // the list to re-centre it would yank it away.
                                    skipAutoScroll = true
                                    onSelectHeading(h.id)
                                }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: sectionState.current) { _, newValue in
                    guard let id = newValue else { return }
                    guard !skipAutoScroll else {
                        skipAutoScroll = false
                        return
                    }
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var results: some View {
        if search.matches.isEmpty {
            placeholder(String(localized: "Nothing matches “\(search.query)”"))
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(search.matches) { match in
                            ResultRow(match: match, isSelected: match.id == search.currentIndex)
                                .id(match.id)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectMatch(match.id) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: search.currentIndex) { _, index in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private func placeholder(_ text: String) -> some View {
        VStack {
            Spacer()
            Text(verbatim: text)
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ResultRow: View {
    let match: SearchMatch
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(match.sectionTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            (
                Text(match.prefix).foregroundColor(.secondary)
                    + Text(match.match).foregroundColor(.primary).fontWeight(.semibold)
                    + Text(match.suffix).foregroundColor(.secondary)
            )
            .font(.system(size: 11))
            .lineLimit(2)
            .truncationMode(.tail)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }
}

private struct HeadingRow: View {
    let heading: MarkdownDocument.Heading
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text(heading.text)
                .font(font(for: heading.level, selected: isSelected))
                .foregroundStyle(color(for: heading.level, selected: isSelected))
                .lineLimit(2)
                .padding(.vertical, 5)
                .padding(.leading, 10 + indent(for: heading.level))
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.secondary.opacity(0.18) : Color.clear)
        )
    }

    private func font(for level: Int, selected: Bool) -> Font {
        let baseWeight: Font.Weight
        switch level {
        case 1: baseWeight = .semibold
        case 2: baseWeight = .medium
        default: baseWeight = .regular
        }
        let weight: Font.Weight = selected ? .semibold : baseWeight
        switch level {
        case 1: return .system(size: 13, weight: weight)
        case 2: return .system(size: 12, weight: weight)
        case 3: return .system(size: 12, weight: weight)
        default: return .system(size: 11, weight: weight)
        }
    }

    private func color(for level: Int, selected: Bool) -> Color {
        if selected { return .primary }
        switch level {
        case 1: return .primary
        case 2: return .primary.opacity(0.85)
        case 3: return .secondary
        default: return .secondary.opacity(0.8)
        }
    }

    private func indent(for level: Int) -> CGFloat {
        CGFloat(max(0, level - 1)) * 12
    }
}


/// The same Liquid Glass the toolbar controls sit on, behind the outline.
private struct SidebarBackdrop: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.regular, in: Rectangle())
        } else {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

/// Reading progress, alongside the outline's heading.
///
/// Its own view so that the scroll position — which changes many times a second
/// — only ever invalidates these few points of the window.
private struct ProgressReadout: View {
    @ObservedObject var state: ProgressState

    var body: some View {
        Text(verbatim: "· \(Int(state.value * 100))%")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundStyle(.tertiary)
            // Fixed width: otherwise the bar beside it would shuffle sideways
            // every time the number gained or lost a digit.
            .frame(width: 34, alignment: .leading)
    }
}

private struct ReadingProgressBar: View {
    @ObservedObject var state: ProgressState

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.18))
                Capsule()
                    // Grey rather than the accent colour: it reports, it does not
                    // ask to be looked at.
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: max(3, geo.size.width * state.value))
            }
        }
        .frame(height: 4)
    }
}
