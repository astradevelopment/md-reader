import CoreGraphics

/// How the tab strip divides itself between what is shown and what collapses into
/// the overflow menu. Pure and free of SwiftUI so it can be reasoned about — and
/// tested — on its own.
enum TabSplit {
    /// How many tabs to show.
    ///
    /// Two passes, because the overflow menu only exists if something overflows:
    /// first how many fit without it, and only if that is not all of them, how
    /// many fit once it takes its place. Charging a whole tab's width for the
    /// menu — which is a chevron and a number — is what hid tabs while there was
    /// plainly room for them.
    static func fitting(
        count: Int,
        available: CGFloat,
        tabWidth: CGFloat,
        spacing: CGFloat,
        buttonWidth: CGFloat,
        menuWidth: CGFloat
    ) -> Int {
        let room = available - buttonWidth - spacing
        let perTab = tabWidth + spacing
        guard perTab > 0, count > 0 else { return 0 }

        let withoutMenu = Int((room / perTab).rounded(.down))
        if count <= withoutMenu { return count }

        let withMenu = Int(((room - menuWidth - spacing) / perTab).rounded(.down))
        return max(0, min(count, withMenu))
    }

    /// The order after dragging `moving` onto `target`: it takes the target's
    /// place and everything between shifts along, in either direction.
    static func reorder<ID: Hashable>(ids: [ID], moving: ID, onto target: ID) -> [ID] {
        guard moving != target,
              let from = ids.firstIndex(of: moving),
              let to = ids.firstIndex(of: target)
        else { return ids }

        var result = ids
        let dragged = result.remove(at: from)
        result.insert(dragged, at: to)
        return result
    }

    /// Splits `ids` in document order, never hiding `selected`.
    static func split<ID: Hashable>(
        ids: [ID],
        selected: ID?,
        visible slots: Int
    ) -> (visible: [ID], overflow: [ID]) {
        guard ids.count > slots else { return (ids, []) }
        // Nothing fits: everything goes into the menu rather than pushing the
        // toolbar's own controls into the system overflow.
        guard slots > 0 else { return ([], ids) }

        var visible = Set(ids.prefix(slots))

        if let selected, ids.contains(selected), !visible.contains(selected) {
            // Displace the last tab that would have been shown, not an arbitrary one.
            if let displaced = ids.prefix(slots).last {
                visible.remove(displaced)
            }
            visible.insert(selected)
        }

        return (
            ids.filter { visible.contains($0) },
            ids.filter { !visible.contains($0) }
        )
    }
}
