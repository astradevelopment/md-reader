import SwiftUI
import AppKit
import MarkdownUI
import UniformTypeIdentifiers

@MainActor
final class MarkdownDocument: ObservableObject, Identifiable {
    nonisolated let id = UUID()

    @Published var url: URL?
    @Published var content: String = ""
    @Published var headings: [Heading] = []
    @Published var fileName: String = "MD Reader"
    /// Filename without the extension — browsers label tabs with titles, not files.
    @Published var displayName: String = "MD Reader"
    /// Parsed once per document. Rebuilding this on every render used to re-run
    /// the CommonMark parser over the whole file for each scrolled frame.
    @Published private(set) var sections: [Section] = []
    /// Bumped whenever `sections` is replaced, so views can tell documents apart
    /// with a cheap comparison instead of walking the array.
    @Published private(set) var revision: Int = 0

    /// Where the reader was left when this tab was last on screen. Plain stored
    /// properties on purpose — they change on every scroll and must not publish.
    var lastSectionID: String?
    var lastProgress: Double = 0

    struct Heading: Identifiable, Hashable {
        let id: String
        let level: Int
        let text: String
        let lineIndex: Int
    }

    struct Section: Identifiable, Equatable {
        let id: String
        let heading: Heading?
        /// Raw Markdown, kept for search.
        let content: String
        /// Pre-parsed block tree handed straight to MarkdownUI.
        let markdown: MarkdownContent

        static func == (lhs: Section, rhs: Section) -> Bool { lhs.id == rhs.id }
    }

    /// Fills the document from text that has already been read — used by session
    /// restore, which must not surface an alert for a file that has since moved.
    func adopt(text: String, url: URL) {
        self.url = url
        self.content = text
        self.fileName = url.lastPathComponent
        self.displayName = url.deletingPathExtension().lastPathComponent
        self.headings = Self.extractHeadings(text)
        self.sections = Self.splitIntoSections(content: text, headings: self.headings)
        self.revision += 1
    }

    @discardableResult
    func load(url: URL) -> Bool {
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            self.url = url
            self.content = text
            self.fileName = url.lastPathComponent
            self.displayName = url.deletingPathExtension().lastPathComponent
            self.headings = Self.extractHeadings(text)
            self.sections = Self.splitIntoSections(content: text, headings: self.headings)
            self.revision += 1
            self.lastSectionID = nil
            self.lastProgress = 0
            return true
        } catch {
            let alert = NSAlert()
            alert.messageText = String(localized: "Couldn't open file")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
            return false
        }
    }

    static func extractHeadings(_ text: String) -> [Heading] {
        var result: [Heading] = []
        var inFence = false
        var counter: [String: Int] = [:]
        let lines = text.components(separatedBy: "\n")

        for (i, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                inFence.toggle()
                continue
            }
            if inFence { continue }

            // ATX headings
            if let parsed = parseATX(line: raw) {
                let base = slugify(parsed.text)
                let n = counter[base, default: 0]
                let id = n == 0 ? base : "\(base)-\(n)"
                counter[base] = n + 1
                result.append(Heading(id: id, level: parsed.level, text: parsed.text, lineIndex: i))
                continue
            }

            // Setext headings (=== for H1, --- for H2 — must be preceded by text line)
            if i > 0, !lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty {
                if !trimmed.isEmpty,
                   trimmed.allSatisfy({ $0 == "=" }) || trimmed.allSatisfy({ $0 == "-" }) {
                    let level = trimmed.first == "=" ? 1 : 2
                    // Skip false positives: --- is also frontmatter / hr
                    if level == 2 && trimmed.count < 2 { continue }
                    let headingText = lines[i - 1].trimmingCharacters(in: .whitespaces)
                    if headingText.hasPrefix("#") { continue }
                    let base = slugify(headingText)
                    let n = counter[base, default: 0]
                    let id = n == 0 ? base : "\(base)-\(n)"
                    counter[base] = n + 1
                    // adjust: previous addition might have been for the same line as ATX — skip
                    if let last = result.last, last.lineIndex == i - 1 { continue }
                    result.append(Heading(id: id, level: level, text: headingText, lineIndex: i - 1))
                }
            }
        }
        return result
    }

    private static func parseATX(line: String) -> (level: Int, text: String)? {
        // Optional up to 3 leading spaces, 1–6 #, then space, then text
        var idx = line.startIndex
        var leading = 0
        while idx < line.endIndex, line[idx] == " ", leading < 3 {
            idx = line.index(after: idx)
            leading += 1
        }
        var level = 0
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            idx = line.index(after: idx)
            level += 1
        }
        guard level >= 1, level <= 6 else { return nil }
        guard idx < line.endIndex, line[idx] == " " || line[idx] == "\t" else { return nil }
        let rest = line[idx...].trimmingCharacters(in: .whitespaces)
        // strip trailing #'s (closing sequence)
        var text = rest
        while text.hasSuffix("#") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        return (level, text)
    }

    static func slugify(_ s: String) -> String {
        let lower = s.lowercased()
        var out = ""
        var lastDash = false
        for scalar in lower.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                out.append(Character(scalar))
                lastDash = false
            } else if !lastDash {
                out.append("-")
                lastDash = true
            }
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    static func splitIntoSections(content: String, headings: [Heading]) -> [Section] {
        guard !content.isEmpty else { return [] }
        let lines = content.components(separatedBy: "\n")
        guard !headings.isEmpty else {
            return [Section(id: "all", heading: nil, content: content, markdown: MarkdownContent(content))]
        }
        var sections: [Section] = []
        if headings[0].lineIndex > 0 {
            let pre = lines[0..<headings[0].lineIndex].joined(separator: "\n")
            if !pre.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                sections.append(
                    Section(id: "__preamble__", heading: nil, content: pre, markdown: MarkdownContent(pre))
                )
            }
        }
        for (i, h) in headings.enumerated() {
            let end = (i + 1 < headings.count) ? headings[i + 1].lineIndex : lines.count
            let body = lines[h.lineIndex..<end].joined(separator: "\n")
            sections.append(Section(id: h.id, heading: h, content: body, markdown: MarkdownContent(body)))
        }
        return sections
    }
}
