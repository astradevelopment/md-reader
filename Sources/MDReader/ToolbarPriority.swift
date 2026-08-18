import AppKit

/// Tells the toolbar what to sacrifice when it runs short of room.
///
/// SwiftUI gives every item it creates the standard visibility priority, so when
/// the toolbar has to shed something it goes by position and takes the last item
/// — which is the search field and the text size. Inspecting a running window
/// shows why: the sidebar toggle sits at priority 1000 and the split separator at
/// 2000, while both of ours are left at 0.
///
/// AppKit's own mechanism for this is `visibilityPriority`, and it is not exposed
/// through SwiftUI, so the items are found on the live toolbar instead. Ours are
/// the ones SwiftUI identifies with a UUID — everything else is `com.apple.*` or
/// an `NSToolbar*` standard item — and they appear in the order declared: the
/// tabs first, the controls last.
@MainActor
enum ToolbarPriority {
    static func apply() {
        for window in NSApp.windows {
            guard let toolbar = window.toolbar else { continue }

            let ours = toolbar.items.filter {
                UUID(uuidString: $0.itemIdentifier.rawValue) != nil
            }
            guard let controls = ours.last else { continue }

            // The tabs give way first: they have a menu of their own to fall back
            // on, and the file you are reading is named in the window regardless.
            for item in ours.dropLast() where item.visibilityPriority != .low {
                item.visibilityPriority = .low
            }
            // The controls are what you reach for, so they are the last to go.
            if controls.visibilityPriority != .high {
                controls.visibilityPriority = .high
            }
        }
    }
}
