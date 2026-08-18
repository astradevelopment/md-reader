import SwiftUI

struct SidebarView: View {
    @ObservedObject var document: MarkdownDocument
    @ObservedObject var sectionState: SectionState
    @ObservedObject var search: SearchModel

    var onSelectHeading: (String) -> Void
    var onSelectMatch: (Int) -> Void

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
    }

    // MARK: - Header

    private var header: some View {
        Text(showingResults ? resultsTitle : "CONTENTS")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)
    }

    private var resultsTitle: String {
        if search.matches.isEmpty { return "NO RESULTS" }
        return "RESULTS · \(search.matches.count)\(search.didHitLimit ? "+" : "")"
    }

    // MARK: - Table of contents

    @ViewBuilder
    private var contents: some View {
        if document.headings.isEmpty {
            placeholder(document.content.isEmpty ? "No file open" : "No headings found")
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(document.headings) { h in
                            HeadingRow(heading: h, isSelected: sectionState.current == h.id)
                                .id(h.id)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelectHeading(h.id) }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 12)
                }
                .scrollContentBackground(.hidden)
                .onChange(of: sectionState.current) { _, newValue in
                    guard let id = newValue else { return }
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    // MARK: - Search results

    @ViewBuilder
    private var results: some View {
        if search.matches.isEmpty {
            placeholder("Nothing matches “\(search.query)”")
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
            Text(text)
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
