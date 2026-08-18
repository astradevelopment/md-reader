import SwiftUI

/// How much room the tab strip has left after the right-hand clusters.
///
/// A toolbar item is sized to its content rather than being offered a width, so
/// the strip cannot measure its own space. Instead the detail pane reports the
/// window's usable width and each cluster reports what it occupies.
@MainActor
final class ToolbarLayout: ObservableObject {
    /// Toolbar side margins plus the spacers between clusters.
    private static let chrome: CGFloat = 72

    @Published private(set) var availableForTabs: CGFloat = 600
    @Published private(set) var detailWidth: CGFloat = 1000

    private var clusters: [String: CGFloat] = [:]

    // Which clusters still fit, dropped widest-luxury first. The thresholds are
    // set against the range the pane can actually reach: the window will not go
    // below 820 pt, so the pane only gets tight when the sidebar is dragged wide,
    // bottoming out near 400 pt.
    var showsSearch: Bool { detailWidth >= 420 }
    var showsFontSize: Bool { detailWidth >= 500 }
    var showsProgress: Bool { detailWidth >= 620 }

    func reportDetailWidth(_ width: CGFloat) {
        guard abs(detailWidth - width) > 0.5 else { return }
        detailWidth = width
        recompute()
    }

    func reportCluster(_ key: String, width: CGFloat) {
        guard abs((clusters[key] ?? -1) - width) > 0.5 else { return }
        clusters[key] = width
        recompute()
    }

    private func recompute() {
        let controls = clusters.values.reduce(0, +)
        let value = max(120, detailWidth - controls - Self.chrome)
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
        // A cluster hidden by a breakpoint must stop claiming its width, or the
        // tabs would keep making room for something that is no longer there.
        .onDisappear { layout.reportCluster(key, width: 0) }
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
