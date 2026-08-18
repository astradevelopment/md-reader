import CoreGraphics

/// How the tab strip divides itself between what is shown and what collapses into
/// the overflow menu. Pure and free of SwiftUI so it can be reasoned about — and
/// tested — on its own.
enum TabSplit {
    /// How many tabs fit in `available`, given the trailing "open" button.
    static func capacity(
        available: CGFloat,
        tabWidth: CGFloat,
        spacing: CGFloat,
        buttonWidth: CGFloat
    ) -> Int {
        let room = available - buttonWidth - spacing
        let perTab = tabWidth + spacing
        guard perTab > 0 else { return 1 }
        return max(1, Int((room / perTab).rounded(.down)))
    }

    /// Splits `ids` in document order, never hiding `selected`.
    static func split<ID: Hashable>(
        ids: [ID],
        selected: ID?,
        capacity: Int
    ) -> (visible: [ID], overflow: [ID]) {
        guard ids.count > capacity else { return (ids, []) }

        // One slot is spent on the overflow menu itself.
        let slots = max(1, capacity - 1)
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
