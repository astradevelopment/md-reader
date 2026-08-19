import AppKit
import Markdown

/// Значения сняты с `Theme.swift` читалки, чтобы макет было честно сравнивать с
/// тем, что есть сейчас, а не с абстрактным текстом.
enum Palette {
    static let text = NSColor.labelColor
    static let secondary = NSColor.secondaryLabelColor
    static let accent = NSColor.controlAccentColor
    static let codeBlockBg = NSColor.secondaryLabelColor.withAlphaComponent(0.08)
    static let codeInlineBg = NSColor.secondaryLabelColor.withAlphaComponent(0.14)
    static let divider = NSColor.secondaryLabelColor.withAlphaComponent(0.22)
}

extension NSAttributedString.Key {
    /// Своя пометка: по ней потом рисуется полоска цитаты. Проверка того, что
    /// украшения, которых в TextKit нет из коробки, вообще достижимы.
    static let quoteBar = NSAttributedString.Key("mdreader.quoteBar")
    static let codeBackdrop = NSAttributedString.Key("mdreader.codeBackdrop")
}

struct Renderer {
    let base: CGFloat

    func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        let out = NSMutableAttributedString()
        for block in document.children { append(block, to: out, indent: 0) }
        return out
    }

    // MARK: - Блоки

    private func append(_ block: Markup, to out: NSMutableAttributedString, indent: CGFloat) {
        switch block {
        case let heading as Heading:
            let scale: CGFloat = [1: 2.0, 2: 1.5, 3: 1.25, 4: 1.08, 5: 0.95, 6: 0.88][heading.level] ?? 1
            let weight: NSFont.Weight = heading.level == 1 ? .bold : .semibold
            let top: CGFloat = [1: 36, 2: 44, 3: 36, 4: 28, 5: 22, 6: 20][heading.level] ?? 24
            let bottom: CGFloat = [1: 12, 2: 12, 3: 10, 4: 8, 5: 6, 6: 4][heading.level] ?? 8
            let style = paragraphStyle(before: top, after: bottom, lineHeight: 0.1, indent: indent)
            let body = inlines(heading, font: .systemFont(ofSize: base * scale, weight: weight),
                               color: heading.level == 6 ? Palette.secondary : Palette.text)
            body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
            out.append(body)
            out.append(newline(style))

        case let paragraph as Paragraph:
            let style = paragraphStyle(before: 0, after: 16, lineHeight: 0.35, indent: indent)
            let body = inlines(paragraph, font: .systemFont(ofSize: base), color: Palette.text)
            body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
            out.append(body)
            out.append(newline(style))

        case let quote as BlockQuote:
            let start = out.length
            out.append(NSAttributedString(string: "", attributes: [:]))
            for child in quote.children { append(child, to: out, indent: indent + 16) }
            let range = NSRange(location: start, length: out.length - start)
            out.addAttribute(.quoteBar, value: true, range: range)
            out.addAttribute(.foregroundColor, value: Palette.secondary, range: range)

        case let code as CodeBlock:
            // Внутри блока строки разделены переводом строки, и межабзацный
            // отступ раздвинул бы их: он ставится только на закрывающей строке.
            let style = paragraphStyle(before: 8, after: 0, lineHeight: 0.25, indent: indent + 14)
            style.tailIndent = -14
            let closing = paragraphStyle(before: 0, after: 16, lineHeight: 0.25, indent: indent + 14)
            let text = code.code.hasSuffix("\n") ? String(code.code.dropLast()) : code.code
            let body = NSMutableAttributedString(string: text, attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: base * 0.86, weight: .regular),
                .foregroundColor: Palette.text,
                .paragraphStyle: style,
                .codeBackdrop: true,
            ])
            out.append(body)
            out.append(newline(closing, extra: [.codeBackdrop: true]))

        case let list as UnorderedList:
            for (i, item) in list.listItems.enumerated() {
                appendItem(item, number: i, indent: indent, marker: { _ in "•" }, to: out)
            }

        case let list as OrderedList:
            for (i, item) in list.listItems.enumerated() {
                appendItem(item, number: i, indent: indent, marker: { "\($0 + 1)." }, to: out)
            }

        case is ThematicBreak:
            let style = paragraphStyle(before: 24, after: 24, lineHeight: 0, indent: indent)
            out.append(NSAttributedString(string: "\u{00A0}\n", attributes: [
                .font: NSFont.systemFont(ofSize: 1),
                .paragraphStyle: style,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: Palette.divider,
            ]))

        case let table as Table:
            // Таблицы в макете не рисуются: в приложении они станут вложением
            // (NSTextAttachment) с той же SwiftUI-вёрсткой, что сейчас.
            let style = paragraphStyle(before: 8, after: 16, lineHeight: 0.35, indent: indent)
            out.append(NSAttributedString(string: "[таблица: \(table.maxColumnCount) столбца — в приложении будет вложением]\n",
                                          attributes: [.font: NSFont.systemFont(ofSize: base * 0.875),
                                                       .foregroundColor: Palette.secondary,
                                                       .paragraphStyle: style]))

        default:
            for child in block.children { append(child, to: out, indent: indent) }
        }
    }

    private func appendItem(_ item: ListItem, number: Int, indent: CGFloat,
                            marker: (Int) -> String, to out: NSMutableAttributedString) {
        let markerWidth = base * 1.5
        let style = paragraphStyle(before: 10, after: 0, lineHeight: 0.35, indent: indent)
        style.headIndent = indent + markerWidth
        style.firstLineHeadIndent = indent
        style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]

        var first = true
        for child in item.children {
            guard let paragraph = child as? Paragraph else { append(child, to: out, indent: indent + markerWidth); continue }
            let body = NSMutableAttributedString()
            if first {
                body.append(NSAttributedString(string: marker(number) + "\t", attributes: [
                    .font: NSFont.systemFont(ofSize: base), .foregroundColor: Palette.secondary,
                ]))
                first = false
            }
            body.append(inlines(paragraph, font: .systemFont(ofSize: base), color: Palette.text))
            body.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: body.length))
            out.append(body)
            out.append(newline(style))
        }
    }

    // MARK: - Инлайны

    private func inlines(_ node: Markup, font: NSFont, color: NSColor) -> NSMutableAttributedString {
        let out = NSMutableAttributedString()
        for child in node.children {
            switch child {
            case let text as Markdown.Text:
                out.append(NSAttributedString(string: text.string, attributes: [.font: font, .foregroundColor: color]))
            case is SoftBreak:
                out.append(NSAttributedString(string: " ", attributes: [.font: font, .foregroundColor: color]))
            case is LineBreak:
                out.append(NSAttributedString(string: "\n", attributes: [.font: font, .foregroundColor: color]))
            case let strong as Strong:
                out.append(inlines(strong, font: bold(font), color: color))
            case let emphasis as Emphasis:
                out.append(inlines(emphasis, font: italic(font), color: color))
            case let struck as Strikethrough:
                let inner = inlines(struck, font: font, color: Palette.secondary)
                inner.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue,
                                   range: NSRange(location: 0, length: inner.length))
                out.append(inner)
            case let code as InlineCode:
                out.append(NSAttributedString(string: code.code, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.88, weight: .regular),
                    .foregroundColor: color,
                    .backgroundColor: Palette.codeInlineBg,
                ]))
            case let link as Link:
                let inner = inlines(link, font: font, color: Palette.accent)
                let range = NSRange(location: 0, length: inner.length)
                if let destination = link.destination, let url = URL(string: destination) {
                    inner.addAttribute(.link, value: url, range: range)
                }
                inner.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
                out.append(inner)
            case let image as Markdown.Image:
                out.append(NSAttributedString(string: "[картинка: \(image.source ?? "")]",
                                              attributes: [.font: font, .foregroundColor: Palette.secondary]))
            default:
                out.append(inlines(child, font: font, color: color))
            }
        }
        return out
    }

    private func bold(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
    }

    private func italic(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private func paragraphStyle(before: CGFloat, after: CGFloat, lineHeight: CGFloat,
                                indent: CGFloat) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.paragraphSpacingBefore = before
        style.paragraphSpacing = after
        style.lineSpacing = base * lineHeight
        style.headIndent = indent
        style.firstLineHeadIndent = indent
        return style
    }

    private func newline(_ style: NSParagraphStyle,
                         extra: [NSAttributedString.Key: Any] = [:]) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [.paragraphStyle: style,
                                                         .font: NSFont.systemFont(ofSize: base)]
        attributes.merge(extra) { _, new in new }
        return NSAttributedString(string: "\n", attributes: attributes)
    }
}
