import AppKit
import Markdown

/// `NSTextView`, который умеет рисовать то, чего в TextKit нет из коробки:
/// полоску цитаты и скруглённую подложку блока кода. Это и есть проверка
/// «украшения достижимы».
final class ReaderTextView: NSTextView {
    override func draw(_ dirtyRect: NSRect) {
        drawDecorations()
        super.draw(dirtyRect)
    }

    private func drawDecorations() {
        guard let storage = textStorage, let manager = textLayoutManager,
              let container = textContainer else { return }
        let inset = textContainerInset

        storage.enumerateAttribute(.codeBackdrop, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil, let box = boundingBox(range, manager, container) else { return }
            let frame = box.offsetBy(dx: inset.width, dy: inset.height).insetBy(dx: -10, dy: -6)
            let path = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
            Palette.codeBlockBg.setFill(); path.fill()
            Palette.divider.setStroke(); path.lineWidth = 1; path.stroke()
        }

        storage.enumerateAttribute(.quoteBar, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard value != nil, let box = boundingBox(range, manager, container) else { return }
            let bar = NSRect(x: inset.width, y: box.minY + inset.height, width: 3, height: box.height)
            Palette.accent.withAlphaComponent(0.55).setFill()
            NSBezierPath(roundedRect: bar, xRadius: 2, yRadius: 2).fill()
        }
    }

    func debugBox(_ range: NSRange) -> NSRect? {
        guard let manager = textLayoutManager, let container = textContainer else { return nil }
        return boundingBox(range, manager, container)
    }

    private func boundingBox(_ range: NSRange, _ manager: NSTextLayoutManager,
                             _ container: NSTextContainer) -> NSRect? {
        guard let content = manager.textContentManager,
              let start = content.location(content.documentRange.location, offsetBy: range.location),
              let end = content.location(start, offsetBy: range.length),
              let textRange = NSTextRange(location: start, end: end) else { return nil }
        var box: NSRect?
        manager.enumerateTextSegments(in: textRange, type: .standard) { _, frame, _, _ in
            box = box.map { $0.union(frame) } ?? frame
            return true
        }
        return box
    }
}

let sample = """
# Разведка на макете

Обычный абзац, чтобы было что тащить мышью. Он **жирный местами**, местами
*наклонный*, содержит `инлайн-код` и [ссылку на сайт обновлений](https://md.dmind.pro/),
над которой курсор должен стать рукой.

Второй абзац идёт следом. Главная проверка: выделение, начатое в первом абзаце,
должно дотянуться сюда и дальше — через заголовок, список и блок кода.

## Заголовок второго уровня

- Первый пункт списка
- Второй пункт, подлиннее, чтобы увидеть, как переносится строка и держится ли
  отступ под маркером
- Третий пункт

1. Нумерованный пункт
2. И ещё один

> Цитата с полоской слева. Полоска нарисована руками поверх текста — в TextKit
> такого украшения нет, и это ровно та работа, которую придётся делать.

```swift
let renderer = Renderer(base: 16)
let text = renderer.render(markdown)   // подложка скруглённая, тоже руками
```

---

Абзац после разделителя. Если выделение дошло сюда от самого верха — подложка
годится.
"""

final class Delegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!

    func applicationDidFinishLaunching(_ notification: Notification) {
        let frame = NSRect(x: 0, y: 0, width: 900, height: 760)
        window = NSWindow(contentRect: frame,
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        window.title = "Макет: один NSTextView"
        window.center()

        let scroll = NSScrollView(frame: frame)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let textView = ReaderTextView(usingTextLayoutManager: true)
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 72, height: 48)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.linkTextAttributes = [
            .foregroundColor: Palette.accent,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
            .cursor: NSCursor.pointingHand,
        ]
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true

        let rendered = Renderer(base: 16).render(sample)
        textView.textStorage?.setAttributedString(rendered)

        scroll.documentView = textView
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        if ProcessInfo.processInfo.environment["PROBE_CHECK"] == "1" {
            check(textView, rendered)
        }
    }

    /// То, что можно доказать без мыши: одно хранилище — значит диапазон
    /// выделения свободно пересекает границы абзацев и блоков.
    private func check(_ textView: NSTextView, _ rendered: NSAttributedString) {
        let full = NSRange(location: 0, length: rendered.length)
        textView.setSelectedRange(full)
        let taken = (textView.string as NSString).substring(with: textView.selectedRange())
        let paragraphs = taken.split(separator: "\n").count
        print("абзацев в документе   : \(paragraphs)")
        print("символов в выделении  : \(taken.count)")

        // Считаются ли прямоугольники украшений — или боксы выходят пустыми.
        if let manager = textView.textLayoutManager, let storage = textView.textStorage {
            manager.ensureLayout(for: manager.documentRange)
            for key in [NSAttributedString.Key.codeBackdrop, .quoteBar] {
                var found = 0, boxed = 0
                storage.enumerateAttribute(key, in: full) { value, range, _ in
                    guard value != nil else { return }
                    found += 1
                    if (textView as? ReaderTextView)?.debugBox(range) != nil { boxed += 1 }
                }
                print("украшение \(key.rawValue): диапазонов \(found), с прямоугольником \(boxed)")
            }
        }

        var links = 0
        rendered.enumerateAttribute(.link, in: full) { value, _, _ in if value != nil { links += 1 } }
        print("ссылок с атрибутом    : \(links)")

        // Выделение поперёк границы: конец первого абзаца + начало второго.
        let text = textView.string as NSString
        let firstBreak = text.range(of: "\n", options: [], range: NSRange(location: 40, length: text.length - 40))
        if firstBreak.location != NSNotFound {
            let across = NSRange(location: firstBreak.location - 20, length: 60)
            textView.setSelectedRange(across)
            let piece = text.substring(with: textView.selectedRange())
            print("поперёк границы       : \(piece.contains("\n") ? "да" : "нет") — «\(piece.replacingOccurrences(of: "\n", with: "⏎"))»")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
    }
}

let app = NSApplication.shared
let delegate = Delegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
