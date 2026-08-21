import SwiftUI

/// How much room the tab strip has left beside the toolbar's controls.
///
/// A toolbar item is sized to its content rather than being offered a width, so
/// the strip cannot measure its own space. The detail pane reports the usable
/// width instead, and the controls report what they occupy.
@MainActor
final class ToolbarLayout: ObservableObject {
    /// The toolbar's own furniture: side margins, spacers, and the sidebar toggle
    /// that sits ahead of the tabs.
    private static let chrome: CGFloat = 112

    /// Room always kept for the controls — enough for them at rest, not at their
    /// widest.
    ///
    /// Holding back the full 470 pt that an open search field needs left the tabs
    /// permanently cramped, truncating names of ten characters while half the
    /// toolbar stood empty. They can afford to give way when search opens, now
    /// that `ToolbarPriority` guarantees the controls are never what the toolbar
    /// drops.
    private static let controlsReserve: CGFloat = 200

    @Published private(set) var availableForTabs: CGFloat = 600
    @Published private(set) var detailWidth: CGFloat = 1000

    private var controlsWidth: CGFloat = 0

    /// The narrowest the pane can honestly be: the window stops at 960 pt and the
    /// sidebar at 320. Anything smaller is a half-built layout reporting itself
    /// mid-pass — believing it hides every tab behind the overflow menu while the
    /// window is plainly wide.
    private static let plausibleMinimum: CGFloat = 240

    func reportDetailWidth(_ width: CGFloat) {
        guard width > Self.plausibleMinimum else { return }
        guard abs(detailWidth - width) > 0.5 else { return }
        detailWidth = width
        recompute()
    }

    func reportCluster(_ key: String, width: CGFloat) {
        // Zero means the item is not on screen — being redrawn, or taken into the
        // overflow. Never a real measurement.
        guard width > 1, abs(controlsWidth - width) > 0.5 else { return }
        controlsWidth = width
        recompute()
    }

    private func recompute() {
        let controls = max(controlsWidth, Self.controlsReserve)
        // The strip runs up to the controls, not to half the pane. Half was a
        // guess that bound long before the arithmetic did: on a 921 pt pane the
        // subtraction left 609 and the fraction cut it to 460, hiding a fourth
        // tab while a third of the toolbar stood empty. What protects the
        // controls is the reserve above and `ToolbarPriority`, not this ceiling —
        // it stays only so a narrow pane cannot be taken over entirely.
        let value = min(max(60, detailWidth - controls - Self.chrome), detailWidth * 0.85)
        // A coarse threshold: the search field animates its width open and shut,
        // and republishing every frame of that would churn the whole toolbar.
        guard abs(value - availableForTabs) > 8 else { return }
        availableForTabs = value
    }
}

extension View {
    func measureCluster(_ key: String, into layout: ToolbarLayout) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
            layout.reportCluster(key, width: width)
        }
    }
}

/// The tab the pointer is over, with its position in window coordinates.
@MainActor
final class TabHoverState: ObservableObject {
    struct Info: Equatable {
        let id: UUID
        let name: String
        let anchor: CGRect
        /// The opening of the document, for the preview. Already parsed, so
        /// showing it costs no more than drawing it.
        let opening: [MarkdownDocument.Block]
    }

    @Published var info: Info?

    func enter(id: UUID, name: String, anchor: CGRect, opening: [MarkdownDocument.Block]) {
        info = Info(id: id, name: name, anchor: anchor, opening: opening)
    }

    func leave(id: UUID) {
        if info?.id == id { info = nil }
    }
}
