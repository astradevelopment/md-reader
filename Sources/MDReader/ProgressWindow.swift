import AppKit

/// A small panel for the seconds an update takes, so the app does not simply
/// appear to have frozen before it restarts itself.
@MainActor
final class ProgressWindow {
    private let panel: NSPanel

    init(message: String) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 280, height: 92),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.level = .floating

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 12)

        let row = NSStackView(views: [spinner, label])
        row.orientation = .horizontal
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false

        let content = NSView()
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            row.centerYAnchor.constraint(equalTo: content.centerYAnchor),
        ])
        panel.contentView = content
    }

    func show() {
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel.orderOut(nil)
    }
}
