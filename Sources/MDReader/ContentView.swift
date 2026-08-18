import SwiftUI

struct ContentView: View {
    @ObservedObject var store: DocumentStore
    @ObservedObject private var settings = ReaderSettings.shared

    /// Held as plain `@State`: these are reference types, so ContentView stores them
    /// without subscribing. Only the small views that actually render their values
    /// observe them, which keeps scrolling and typing off the document's redraw path.
    @State private var progressState = ProgressState()
    @State private var sectionState = SectionState()
    @State private var search = SearchModel()

    @State private var scrollRequest: ScrollRequest?
    @State private var scrollToken = 0
    /// Unobserved here: only the tab strip cares how much room is left.
    @State private var toolbarLayout = ToolbarLayout()
    @State private var tabHover = TabHoverState()

    var body: some View {
        NavigationSplitView {
            sidebar
                // Capped so that even at its widest the pane still fits the toolbar.
            .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 320)
        } detail: {
            ZStack(alignment: .topLeading) {
                detail
                // A sibling, not an overlay on `detail`: only this layer redraws
                // when the pointer moves across the tabs.
                TabTooltipLayer(hover: tabHover)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width in
                toolbarLayout.reportDetailWidth(width)
            }
        }
        .navigationTitle("")
        .toolbar {
            if !store.isEmpty {
                tabsItem
            }
            if store.selected != nil {
                toolbarControls
            }
        }
        .onAppear { adoptSelection() }
        .onChange(of: store.selectedID) { _, _ in adoptSelection() }
        .onChange(of: store.selected?.revision) { _, _ in adoptSelection() }
        .onReceive(NotificationCenter.default.publisher(for: .mdrFind)) { _ in
            search.isPresented = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdrFindNext)) { _ in
            guard search.isPresented else { return }
            search.next()
            jumpToCurrentMatch()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mdrFindPrevious)) { _ in
            guard search.isPresented else { return }
            search.previous()
            jumpToCurrentMatch()
        }
    }

    // MARK: - Panes

    @ViewBuilder
    private var sidebar: some View {
        if let document = store.selected {
            SidebarView(
                document: document,
                sectionState: sectionState,
                progressState: progressState,
                search: search,
                onSelectHeading: { id in jump(to: id, flash: false) },
                onSelectMatch: { index in
                    search.select(index)
                    jumpToCurrentMatch()
                }
            )
        } else {
            SidebarPlaceholder()
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let document = store.selected {
            ReaderView(
                document: document,
                settings: settings,
                progressState: progressState,
                sectionState: sectionState,
                scrollRequest: $scrollRequest,
                onOpenFile: { store.open(url: $0) }
            )
            // Each tab gets its own reader state; scroll position is restored from
            // the document itself.
            .id(document.id)
        } else {
            EmptyStateView(store: store)
        }
    }

    // MARK: - Toolbar

    /// Leading edge of the content area, where the document's own text starts.
    /// The shared background is switched off so the tabs sit directly on the
    /// toolbar instead of on a capsule of their own.
    @ToolbarContentBuilder
    private var tabsItem: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .navigation) {
                TabStrip(store: store, layout: toolbarLayout, hover: tabHover)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) {
                TabStrip(store: store, layout: toolbarLayout, hover: tabHover)
            }
        }
    }

    /// Three separate capsules — search, text size, reading progress.
    ///
    /// macOS 26 would otherwise merge adjacent toolbar items into one shared glass
    /// container, so the shared background is switched off and each control carries
    /// its own, split by fixed spacers.
    @ToolbarContentBuilder
    private var toolbarControls: some ToolbarContent {
        if #available(macOS 26.0, *) {
            // Without this the clusters trail the tabs instead of sitting at the
            // window's edge.
            ToolbarSpacer(.flexible, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                controlClusters
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .primaryAction) {
                controlClusters
            }
        }
    }

    /// Search and text size, in a single toolbar item.
    ///
    /// As separate items, a narrow window let NSToolbar sweep them into its own
    /// overflow popover, where a glass capsule renders as a mangled control. As
    /// one item there is nothing to redistribute, and neither ever goes away:
    /// reading progress moved to the sidebar to leave them the room.
    private var controlClusters: some View {
        HStack(spacing: 8) {
            SearchBar(search: search, onJump: jumpToCurrentMatch)
            FontSizeControl(settings: settings)
        }
        .measureCluster("controls", into: toolbarLayout)
    }

    // MARK: - Actions

    /// Re-points the shared reader state at whichever tab is now in front.
    private func adoptSelection() {
        guard let document = store.selected else {
            search.setCorpus([])
            progressState.value = 0
            sectionState.current = nil
            return
        }
        search.setCorpus(document.sections)
        progressState.value = document.lastProgress
        sectionState.current = document.lastSectionID ?? document.headings.first?.id
    }

    private func jumpToCurrentMatch() {
        guard let match = search.current else { return }
        jump(to: match.sectionID, flash: true)
    }

    private func jump(to sectionID: String, flash: Bool) {
        scrollToken += 1
        sectionState.current = sectionID
        scrollRequest = ScrollRequest(sectionID: sectionID, token: scrollToken, flash: flash)
    }
}

struct SidebarPlaceholder: View {
    var body: some View {
        VStack {
            Spacer()
            Text("No file open")
                .font(.callout)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
