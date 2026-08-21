import SwiftUI

/// How much room the tab strip has left beside the toolbar's controls.
///
/// A toolbar item is sized to its content rather than being offered a width, so
/// the strip cannot measure its own space. The detail pane reports the usable
/// width instead, and the controls report what they occupy.
@MainActor
final class ToolbarLayout: ObservableObject {
    /// Kept clear between the strip and the controls so the two never touch.
    private static let gap: CGFloat = 16

    /// Asked for slightly less than the measurement allows. Toolbar item widths
    /// are rounded and the glass capsules carry their own padding; asking for the
    /// exact limit is what lets the toolbar decide nothing fits.
    private static let cushion: CGFloat = 8

    /// How much room is given up each time the tabs are caught in the system
    /// overflow. Recovery matters more than precision here.
    private static let backoffStep: CGFloat = 48

    /// Starts near nothing on purpose. The strip is given an exact width, so a
    /// generous default is a request for room the toolbar may not have during the
    /// first layout pass — and one overshoot is enough to lose the item into the
    /// overflow popover, from where its view no longer relays out. It grows on the
    /// first measurement, a fifth of a second later.
    @Published private(set) var availableForTabs: CGFloat = 120
    @Published private(set) var detailWidth: CGFloat = 1000

    /// Bumped when the tabs have to be rebuilt. An item swept into the popover
    /// stops laying out, so shrinking alone never brings it back — SwiftUI has to
    /// be made to create it afresh.
    @Published private(set) var rebuildToken: Int = 0

    private var controlsWidth: CGFloat = 0
    /// Where the two items actually sit, in window coordinates. Measured rather
    /// than derived: the furniture ahead of the tabs changes with the sidebar,
    /// and every constant guessed for it has been wrong at some window width.
    /// Everything on the toolbar that is neither the tabs nor the controls: the
    /// sidebar toggle, the flexible spacer's own minimum, and the margins on both
    /// sides. The visible parts measure about 84 pt; the rest is deliberate slack,
    /// because the subtraction otherwise sums exactly to the pane and leaves none —
    /// with the search field open that was enough to lose an item. Kept high,
    /// because overshooting is not a cosmetic error — the toolbar answers it by
    /// sweeping a whole item into its popover, and a swept item's view stops
    /// laying out, so it cannot shrink its way back.
    private static let furniture: CGFloat = 180

    /// The controls at their narrowest, for the moment before they report.
    private static let controlsFloor: CGFloat = 156

    /// Enough for the overflow chevron, the + button and the space between them.
    private static let floor: CGFloat = 96
    private var backoff: CGFloat = 0

    /// The narrowest the pane can honestly be: the window stops at 960 pt and the
    /// sidebar at 320. Anything smaller is a half-built layout reporting itself
    /// mid-pass — believing it hides every tab behind the overflow menu while the
    /// window is plainly wide.
    private static let plausibleMinimum: CGFloat = 240

    func reportDetailWidth(_ width: CGFloat) {
        guard width > Self.plausibleMinimum else { return }
        guard abs(detailWidth - width) > 0.5 else { return }
        // A real resize is a fresh chance: whatever forced a back-off may no
        // longer apply, and without this the strip would stay shrunken for good.
        // Small reports are not resizes — they are the layout settling, and
        // clearing the back-off on those would undo the escape from an overflow.
        if abs(detailWidth - width) > 40 { backoff = 0 }
        detailWidth = width
        recompute()
    }

    /// Only the controls' width is taken from SwiftUI, and only to react faster
    /// than the poll: the controls are pinned to the trailing edge, so every point
    /// they gain is a point their left edge takes from the strip. Waiting half a
    /// second for the next measurement would leave the strip too wide meanwhile —
    /// and too wide, once, is a one-way trip into the overflow popover.
    func reportCluster(_ key: String, frame: CGRect) {
        // Zero means the item is not on screen — being redrawn, or taken into the
        // overflow. Never a real measurement.
        guard frame.width > 1, abs(controlsWidth - frame.width) > 0.5 else { return }
        controlsWidth = frame.width
        recompute()
    }

    /// Room measured on the live toolbar, from AppKit, between where the tabs
    /// start and where the controls start.
    ///
    /// Deliberately not measured from inside the SwiftUI layout: the strip's own
    /// frame depends on the width this class publishes, so reading it there fed
    /// the value back into itself and spun the main thread at full tilt — the
    /// window drew, but nothing scheduled ever ran again.
    /// Called with what the live toolbar is actually showing. If the tabs are not
    /// among the visible items, the toolbar has swept the whole strip into its own
    /// popover — pills inside a system menu. Give room back until it returns.
    func noteTabs(visible: Bool) {
        guard !visible else { return }
        // Bounded: past this the strip would be narrower than a single tab, and
        // something other than width is wrong.
        guard backoff < 400 else { return }
        backoff += Self.backoffStep
        recompute()
        // Shrinking is not enough on its own: the swept item is frozen at the
        // width it had when it left. Rebuilding is what actually brings it back.
        rebuildToken += 1
    }

    private func recompute() {
        // From the one thing worth measuring — how much the controls actually take
        // — rather than from where the items happen to sit. Positions were tried
        // and are a trap: the tabs' own position moves with the width published
        // here, so reading it feeds the value back into itself.
        let controls = max(controlsWidth, Self.controlsFloor)
        let room = detailWidth - controls - Self.furniture - backoff
        // The share is the belt to the subtraction's braces, and it earns its keep
        // on wide windows: there the subtraction would hand the strip everything
        // and the tabs, growing to fill it, left the controls six points to live
        // in — measured on a 1512 pt pane, where the toolbar answered by sweeping
        // the controls away instead. Tabs do not need the whole toolbar.
        // The floor keeps the strip alive rather than pretty: at the narrowest
        // window with the search field open there is no room for tabs, and a strip
        // that asks for nothing is dropped from the toolbar altogether — the
        // chevron holding the other documents and the + button go with it.
        let value = min(max(Self.floor, room), detailWidth * 0.6)

        // A coarse threshold: the search field animates its width open and shut,
        // and republishing every frame of that would churn the whole toolbar.
        guard abs(value - availableForTabs) > 8 else { return }
        availableForTabs = value
    }
}

extension View {
    /// Frames, not widths: where an item sits is what tells the strip how much
    /// room there is between it and the controls.
    func measureCluster(_ key: String, into layout: ToolbarLayout) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            layout.reportCluster(key, frame: frame)
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
