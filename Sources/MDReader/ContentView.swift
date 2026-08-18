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

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
        }
        .navigationTitle(store.selected?.fileName ?? "MD Reader")
        .toolbar {
            if !store.isEmpty {
                // Centre of the toolbar row: the tabs stand in for the window title.
                ToolbarItem(placement: .principal) {
                    TabStrip(store: store)
                }
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

    /// Three separate capsules — search, text size, reading progress.
    ///
    /// macOS 26 would otherwise merge adjacent toolbar items into one shared glass
    /// container, so the shared background is switched off and each control carries
    /// its own, split by fixed spacers.
    @ToolbarContentBuilder
    private var toolbarControls: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .primaryAction) {
                SearchBar(search: search, onJump: jumpToCurrentMatch)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                FontSizeControl(settings: settings)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.fixed, placement: .primaryAction)

            ToolbarItem(placement: .primaryAction) {
                ProgressPill(state: progressState)
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItemGroup(placement: .primaryAction) {
                SearchBar(search: search, onJump: jumpToCurrentMatch)
                FontSizeControl(settings: settings)
                ProgressPill(state: progressState)
            }
        }
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
