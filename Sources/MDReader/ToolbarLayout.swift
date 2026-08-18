import SwiftUI

/// How much room the tab strip has left after the right-hand clusters.
///
/// A toolbar item is sized to its content rather than being offered a width, so
/// the strip cannot measure its own space. Instead the detail pane reports the
/// window's usable width and each cluster reports what it occupies.
@MainActor
final class ToolbarLayout: ObservableObject {
    /// The toolbar's own furniture: side margins, the spacers between clusters
    /// and the sidebar toggle that sits ahead of the tabs. Generous on purpose —
    /// underestimating it is what let the system overflow appear at all.
    private static let chrome: CGFloat = 112

    @Published private(set) var availableForTabs: CGFloat = 600
    @Published private(set) var detailWidth: CGFloat = 1000

    private var clusters: [String: CGFloat] = [:]

    func reportDetailWidth(_ width: CGFloat) {
        guard abs(detailWidth - width) > 0.5 else { return }
        detailWidth = width
        recompute()
    }

    func reportCluster(_ key: String, width: CGFloat) {
        // A cluster is never really zero wide. It measures as zero the moment the
        // toolbar takes it into its overflow popover — and believing that would
        // hand its width to the tabs, which is exactly what keeps it there. A
        // latch: once overflowed, never recovered.
        guard width > 1 else { return }
        guard abs((clusters[key] ?? -1) - width) > 0.5 else { return }
        clusters[key] = width
        recompute()
    }

    private func recompute() {
        let controls = clusters.values.reduce(0, +)
        // Never more than half the pane, whatever the arithmetic says: the tabs
        // are the part that can afford to give way.
        let value = min(max(120, detailWidth - controls - Self.chrome), detailWidth * 0.5)
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
