import Foundation

/// Cutting a section into the blocks it is made of — paragraphs, lists, tables,
/// code — so a search hit can be pointed at one of them rather than at the whole
/// stretch between two headings.
///
/// Pure and free of SwiftUI, because the rules that make it safe are worth
/// testing: a blank line usually ends a block, but not inside a fence, and two
/// list blocks split apart would restart their own numbering.
enum MarkdownBlocks {
    static func split(_ text: String) -> [String] {
        let lines = text.components(separatedBy: "\n")
        var blocks: [[String]] = []
        var current: [String] = []
        var fence: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let marker = fence {
                current.append(line)
                if trimmed.hasPrefix(marker) { fence = nil }
                continue
            }

            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                fence = String(trimmed.prefix(3))
                current.append(line)
                continue
            }

            if trimmed.isEmpty {
                if !current.isEmpty {
                    blocks.append(current)
                    current = []
                }
                continue
            }

            current.append(line)
        }
        if !current.isEmpty { blocks.append(current) }

        return merge(blocks).map { $0.joined(separator: "\n") }
    }

    /// Rejoins what must not have been separated. A list broken in two renders as
    /// two lists and starts counting again from one; indented code broken in two
    /// stops being code at all. The blank line is put back so the markdown still
    /// reads the way it was written.
    private static func merge(_ blocks: [[String]]) -> [[String]] {
        var result: [[String]] = []

        for block in blocks {
            guard let previous = result.last,
                  continues(previous, with: block)
            else {
                result.append(block)
                continue
            }
            result[result.count - 1] = previous + [""] + block
        }
        return result
    }

    private static func continues(_ previous: [String], with block: [String]) -> Bool {
        guard let last = previous.last, let first = block.first else { return false }
        if isListItem(first) && previous.contains(where: isListItem) { return true }
        if isIndentedCode(first) && isIndentedCode(last) { return true }
        return false
    }

    private static func isListItem(_ line: String) -> Bool {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if let first = trimmed.first, "-*+".contains(first) {
            return trimmed.dropFirst().first == " "
        }
        // "1." or "1)"
        let digits = trimmed.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return false }
        let rest = trimmed.dropFirst(digits.count)
        guard let marker = rest.first, marker == "." || marker == ")" else { return false }
        return rest.dropFirst().first == " "
    }

    private static func isIndentedCode(_ line: String) -> Bool {
        line.hasPrefix("    ") || line.hasPrefix("\t")
    }
}
