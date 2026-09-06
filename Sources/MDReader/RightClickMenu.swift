import SwiftUI
import AppKit

/// A right-click menu for a view that lives inside the toolbar.
///
/// SwiftUI's `.contextMenu` never appears there, and neither does a menu hung on
/// a view of our own laid over the tab: the toolbar answers the click before the
/// view under the pointer is ever asked, with "Icon and Text / Icon Only" — the
/// display-mode menu, which is not what anyone right-clicking a tab meant.
/// Checked on screen, both times.
///
/// What does get there first is a local event monitor: it sees the click before
/// the window hands it to any view at all. So the menu is opened by hand and the
/// event is swallowed, and everything else — the tap, the drag, the hover —
/// never notices, because only the right button is taken.
struct RightClickMenu: NSViewRepresentable {
    struct Item {
        let title: String
        /// Nothing to run means a separator.
        let action: (() -> Void)?

        static var separator: Item { Item(title: "", action: nil) }

        static func button(_ title: String, _ action: @escaping () -> Void) -> Item {
            Item(title: title, action: action)
        }
    }

    let items: [Item]

    func makeNSView(context: Context) -> Catcher { Catcher() }

    /// Every redraw hands over fresh closures, so the menu acts on the tab as it
    /// is now — not as it was when the pill first appeared.
    func updateNSView(_ view: Catcher, context: Context) {
        view.items = items
    }

    final class Catcher: NSView {
        var items: [Item] = []

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Leaving the window is where the monitor goes back: a tab that
            // scrolled into the overflow menu must stop watching for clicks.
            if window == nil {
                stopWatching()
            } else {
                startWatching()
            }
        }

        private func startWatching() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.rightMouseDown, .leftMouseDown]) { event in
                // Swallowing is reported as a plain answer rather than by
                // handing the event back: an `NSEvent` cannot cross into an
                // isolated call, a `Bool` can.
                let answered = MainActor.assumeIsolated { [weak self] in
                    self?.answer(event) ?? false
                }
                return answered ? nil : event
            }
        }

        private func stopWatching() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        /// Opens the menu if the click belongs to this view, and says so — a
        /// click that was answered here never reaches the toolbar.
        private func answer(_ event: NSEvent) -> Bool {
            guard Self.isContextClick(event),
                  let window, event.window === window,
                  !items.isEmpty
            else { return false }

            let local = convert(event.locationInWindow, from: nil)
            guard bounds.contains(local), let menu = menu(for: event) else { return false }

            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return true
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            guard !items.isEmpty else { return nil }

            let menu = NSMenu()
            for item in items {
                guard let action = item.action else {
                    menu.addItem(.separator())
                    continue
                }
                let entry = NSMenuItem(title: item.title, action: #selector(run(_:)), keyEquivalent: "")
                entry.target = self
                entry.representedObject = Action(action)
                menu.addItem(entry)
            }
            return menu
        }

        @objc private func run(_ sender: NSMenuItem) {
            (sender.representedObject as? Action)?.body()
        }

        /// Control-click is the same gesture on a mouse with one button, and it
        /// arrives as an ordinary left click with a modifier.
        private static func isContextClick(_ event: NSEvent) -> Bool {
            switch event.type {
            case .rightMouseDown:
                return true
            case .leftMouseDown:
                return event.modifierFlags.contains(.control)
            default:
                return false
            }
        }

        /// A closure needs an object to travel in `representedObject`.
        private final class Action {
            let body: () -> Void
            init(_ body: @escaping () -> Void) { self.body = body }
        }
    }
}
