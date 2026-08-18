import SwiftUI

/// Scroll progress, isolated in its own object so that the 60–120 updates per
/// second it receives while scrolling only invalidate the toolbar pill and never
/// the document itself.
@MainActor
final class ProgressState: ObservableObject {
    @Published var value: Double = 0
}

/// The heading currently at the top of the viewport. Separate from `ProgressState`
/// so the sidebar redraws once per section crossing instead of once per frame.
@MainActor
final class SectionState: ObservableObject {
    @Published var current: String?
}

/// A request to scroll the reader to a section. Carries a token so that jumping
/// twice to the same section (e.g. two search hits in one section) still fires.
struct ScrollRequest: Equatable {
    let sectionID: String
    let token: Int
    var flash: Bool = false
}

extension Notification.Name {
    static let mdrFind = Notification.Name("mdr.find")
    static let mdrFindNext = Notification.Name("mdr.findNext")
    static let mdrFindPrevious = Notification.Name("mdr.findPrevious")
}
