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

    /// Room always kept for the controls, whatever they currently measure.
    ///
    /// They are narrow at rest and wide with the search field open, and reserving
    /// only what they take *now* is what let the toolbar overflow: the tabs would
    /// spread into the slack, then search would open with nowhere to go. Worse,
    /// a cluster in the overflow popover stops being drawn, so it stops reporting
    /// a width — leaving the tabs no reason to give the space back. Measured at
    /// its widest — search open, a query typed and the match counter showing — the
    /// cluster is a little under 400 pt, and this keeps a margin over that.
    private static let controlsReserve: CGFloat = 470

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
        // Never more than half the pane either: the tabs are the part that can
        // afford to give way.
        let value = min(max(60, detailWidth - controls - Self.chrome), detailWidth * 0.5)
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
    }

    @Published var info: Info?

    func enter(id: UUID, name: String, anchor: CGRect) {
        info = Info(id: id, name: name, anchor: anchor)
    }

    func leave(id: UUID) {
        if info?.id == id { info = nil }
    }
}
