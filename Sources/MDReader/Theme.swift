import SwiftUI
import MarkdownUI

/// Themes are expensive to build (a closure per block style), so each text size is
/// built once and reused for every section of every document.
@MainActor
enum ThemeCache {
    private static var cache: [Int: Theme] = [:]

    static func reader(fontSize: Double) -> Theme {
        let key = Int(fontSize.rounded())
        if let cached = cache[key] { return cached }
        let theme = Theme.mdReader(fontSize: Double(key))
        cache[key] = theme
        return theme
    }
}

extension Theme {
    /// Notion / Bear-inspired theme for the reader. Every size except the base is
    /// relative, so the whole document scales from `fontSize`.
    @MainActor static func mdReader(fontSize: Double) -> Theme {
        Theme()
        .text {
            // The system face — San Francisco — stated rather than inherited, so a
            // change of default in the library cannot quietly move the text onto
            // something else.
            FontFamily(.system())
            ForegroundColor(.primary)
            FontSize(fontSize)
        }
        .code {
            FontFamilyVariant(.monospaced)
            FontSize(.em(0.88))
            ForegroundColor(.codeText)
            BackgroundColor(.codeInlineBg)
        }
        .strong {
            FontWeight(.semibold)
        }
        .emphasis {
            FontStyle(.italic)
        }
        .strikethrough {
            StrikethroughStyle(.single)
            ForegroundColor(.secondary)
        }
        .link {
            ForegroundColor(.accent)
            UnderlineStyle(.single)
        }
        .heading1 { config in
            VStack(alignment: .leading, spacing: 0) {
                config.label
                    .relativeLineSpacing(.em(0.1))
                    .markdownMargin(top: 36, bottom: 12)
                    .markdownTextStyle {
                        FontWeight(.bold)
                        FontSize(.em(2.0))
                    }
                Divider().overlay(Color.dividerSoft)
                    .padding(.top, 2)
            }
        }
        .heading2 { config in
            config.label
                .relativeLineSpacing(.em(0.1))
                .markdownMargin(top: 44, bottom: 12)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.5))
                }
        }
        .heading3 { config in
            config.label
                .relativeLineSpacing(.em(0.1))
                .markdownMargin(top: 36, bottom: 10)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.25))
                }
        }
        .heading4 { config in
            config.label
                .markdownMargin(top: 28, bottom: 8)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(1.08))
                }
        }
        .heading5 { config in
            config.label
                .markdownMargin(top: 22, bottom: 6)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.95))
                }
        }
        .heading6 { config in
            config.label
                .markdownMargin(top: 20, bottom: 4)
                .markdownTextStyle {
                    FontWeight(.semibold)
                    FontSize(.em(0.88))
                    ForegroundColor(.secondary)
                }
        }
        .paragraph { config in
            config.label
                .fixedSize(horizontal: false, vertical: true)
                .relativeLineSpacing(.em(0.35))
                .markdownMargin(top: 0, bottom: 16)
        }
        .blockquote { config in
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(0.55))
                    .frame(width: 3)
                config.label
                    .markdownTextStyle { ForegroundColor(.secondary) }
                    .relativePadding(.horizontal, length: .em(1))
            }
            .fixedSize(horizontal: false, vertical: true)
            .markdownMargin(top: 4, bottom: 16)
        }
        .codeBlock { config in
            VStack(alignment: .leading, spacing: 0) {
                if let lang = config.language, !lang.isEmpty {
                    Text(lang.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                }
                // `.basedOnSize` keeps short code blocks from swallowing the
                // trackpad gesture and stalling the outer scroll.
                ScrollView(.horizontal, showsIndicators: false) {
                    config.label
                        .fixedSize(horizontal: false, vertical: true)
                        .relativeLineSpacing(.em(0.25))
                        .markdownTextStyle {
                            FontFamilyVariant(.monospaced)
                            FontSize(.em(0.86))
                            ForegroundColor(.codeText)
                        }
                        .padding(14)
                }
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            }
            .background(Color.codeBlockBg)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.dividerSoft, lineWidth: 1)
            )
            .markdownMargin(top: 8, bottom: 16)
        }
        .listItem { config in
            config.label
                .markdownMargin(top: 0, bottom: 6)
        }
        .taskListMarker { config in
            Image(systemName: config.isCompleted ? "checkmark.square.fill" : "square")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(config.isCompleted ? Color.accentColor : Color.secondary)
                .imageScale(.medium)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .bulletedListMarker { _ in
            Text(verbatim: "•")
                .foregroundStyle(.secondary)
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .numberedListMarker { config in
            Text(verbatim: "\(config.itemNumber).")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .relativeFrame(minWidth: .em(1.5), alignment: .trailing)
        }
        .table { config in
            config.label
                .fixedSize(horizontal: false, vertical: true)
                .markdownTableBorderStyle(.init(color: .dividerSoft))
                .markdownTableBackgroundStyle(
                    .alternatingRows(Color.clear, Color.tableAlt)
                )
                .markdownMargin(top: 8, bottom: 16)
        }
        .tableCell { config in
            config.label
                .markdownTextStyle {
                    FontSize(.em(0.875))
                    if config.row == 0 {
                        FontWeight(.semibold)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
        }
        .thematicBreak {
            Divider().overlay(Color.dividerSoft)
                .markdownMargin(top: 24, bottom: 24)
        }
        .image { config in
            config.label
                .frame(maxWidth: .infinity)
                .markdownMargin(top: 8, bottom: 8)
        }
    }
}

extension Color {
    static let codeText = Color.primary
    static let codeInlineBg = Color.secondary.opacity(0.14)
    static let codeBlockBg = Color.secondary.opacity(0.08)
    static let dividerSoft = Color.secondary.opacity(0.22)
    static let tableAlt = Color.secondary.opacity(0.06)
    static let accent = Color.accentColor
}
