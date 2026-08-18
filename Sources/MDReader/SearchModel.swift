import SwiftUI

struct SearchMatch: Identifiable, Equatable {
    let id: Int
    let sectionID: String
    let sectionTitle: String
    /// Text before the hit on the same line, already trimmed for display.
    let prefix: String
    let match: String
    let suffix: String
}

/// Full-text search over the open document.
///
/// Owned by `ContentView` as plain `@State` (i.e. *not* observed there), so typing
/// only redraws the search field and the results list — never the rendered document.
@MainActor
final class SearchModel: ObservableObject {
    private struct Entry {
        let id: String
        let title: String
        let lines: [String]
    }

    /// Beyond this we stop scanning — a query like "a" would otherwise produce
    /// thousands of useless hits.
    private static let matchLimit = 400
    private static let minQueryLength = 2

    @Published var isPresented = false {
        didSet { if !isPresented { query = "" } }
    }
    @Published var query: String = "" {
        didSet { guard query != oldValue else { return }; rebuild() }
    }
    @Published private(set) var matches: [SearchMatch] = []
    @Published private(set) var currentIndex: Int = 0
    @Published private(set) var didHitLimit = false

    private var corpus: [Entry] = []

    var current: SearchMatch? {
        matches.indices.contains(currentIndex) ? matches[currentIndex] : nil
    }

    var hasQuery: Bool {
        query.trimmingCharacters(in: .whitespaces).count >= Self.minQueryLength
    }

    func setCorpus(_ sections: [MarkdownDocument.Section]) {
        corpus = sections.map {
            Entry(
                id: $0.id,
                title: $0.heading?.text ?? "Beginning",
                lines: $0.content.components(separatedBy: "\n")
            )
        }
        rebuild()
    }

    func select(_ index: Int) {
        guard matches.indices.contains(index) else { return }
        currentIndex = index
    }

    @discardableResult
    func next() -> SearchMatch? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex + 1) % matches.count
        return current
    }

    @discardableResult
    func previous() -> SearchMatch? {
        guard !matches.isEmpty else { return nil }
        currentIndex = (currentIndex - 1 + matches.count) % matches.count
        return current
    }

    func dismiss() {
        isPresented = false
    }

    private func rebuild() {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.count >= Self.minQueryLength else {
            if !matches.isEmpty { matches = [] }
            currentIndex = 0
            didHitLimit = false
            return
        }

        var found: [SearchMatch] = []
        var limited = false
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        scan: for entry in corpus {
            for line in entry.lines {
                // Fence markers carry no meaning for the reader.
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { continue }

                var cursor = line.startIndex
                while let range = line.range(of: needle, options: options, range: cursor..<line.endIndex) {
                    if found.count >= Self.matchLimit {
                        limited = true
                        break scan
                    }
                    found.append(
                        SearchMatch(
                            id: found.count,
                            sectionID: entry.id,
                            sectionTitle: entry.title,
                            prefix: Self.leadIn(of: line, upTo: range.lowerBound),
                            match: String(line[range]),
                            suffix: String(line[range.upperBound...].prefix(70))
                        )
                    )
                    cursor = range.upperBound
                    if cursor >= line.endIndex { break }
                }
            }
        }

        matches = found
        currentIndex = 0
        didHitLimit = limited
    }

    /// The tail of the line before the hit, with heading/list punctuation stripped
    /// so a snippet reads as prose rather than as raw Markdown.
    private static func leadIn(of line: String, upTo index: String.Index) -> String {
        let head = String(line[line.startIndex..<index])
        let truncated = head.count > 42
        var text = truncated ? String(head.suffix(42)) : head
        if !truncated {
            text = String(text.drop(while: { "#>*- ".contains($0) }))
        }
        return truncated ? "…" + text : text
    }
}
