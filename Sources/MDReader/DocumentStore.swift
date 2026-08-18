import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Every open file, in tab order, plus the session that gets restored on launch.
@MainActor
final class DocumentStore: ObservableObject {
    /// Shared so the app delegate — which receives the open-files event — and the
    /// SwiftUI scene address the same set of tabs.
    static let shared = DocumentStore()

    @Published private(set) var documents: [MarkdownDocument] = []
    @Published var selectedID: UUID?
    @Published private(set) var recentURLs: [URL] = []

    private static let openFilesKey = "session.openFiles"
    private static let selectedFileKey = "session.selectedFile"
    private static let recentFilesKey = "recent.files"
    private let maxRecent = 15

    var selected: MarkdownDocument? {
        documents.first { $0.id == selectedID }
    }

    var isEmpty: Bool { documents.isEmpty }

    private var didRestore = false

    private init() {
        refreshRecentURLs()
    }

    func openAll(_ urls: [URL]) {
        for url in urls { open(url: url, persist: false) }
        persistSession()
    }

    // MARK: - Opening

    /// Focuses the tab if the file is already open, otherwise adds one.
    @discardableResult
    func open(url: URL, persist: Bool = true) -> MarkdownDocument? {
        let target = url.standardizedFileURL

        if let existing = documents.first(where: { $0.url?.standardizedFileURL == target }) {
            selectedID = existing.id
            // Re-opening an already-open file still counts as using it.
            noteRecent(target)
            if persist { persistSession() }
            return existing
        }

        let document = MarkdownDocument()
        guard document.load(url: target) else { return nil }

        documents.append(document)
        selectedID = document.id
        noteRecent(target)
        if persist { persistSession() }
        return document
    }

    func openPanel() {
        let panel = NSOpenPanel()
        let md = UTType(filenameExtension: "md") ?? .plainText
        let markdown = UTType(filenameExtension: "markdown") ?? .plainText
        panel.allowedContentTypes = [md, markdown, .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            open(url: url, persist: false)
        }
        persistSession()
    }

    // MARK: - Closing and switching

    func close(_ id: UUID) {
        guard let index = documents.firstIndex(where: { $0.id == id }) else { return }
        documents.remove(at: index)

        if selectedID == id {
            // Land on the neighbour to the right, the way browsers do.
            let next = min(index, documents.count - 1)
            selectedID = documents.indices.contains(next) ? documents[next].id : nil
        }
        persistSession()
    }

    /// Closes the current tab, or the window when nothing is left to close.
    func closeSelectedOrWindow() {
        if let selectedID {
            close(selectedID)
        } else {
            NSApp.keyWindow?.performClose(nil)
        }
    }

    func selectNext() { step(by: 1) }
    func selectPrevious() { step(by: -1) }

    private func step(by offset: Int) {
        guard documents.count > 1,
              let current = documents.firstIndex(where: { $0.id == selectedID })
        else { return }
        let next = (current + offset + documents.count) % documents.count
        selectedID = documents[next].id
        persistSession()
    }

    /// Drops the dragged tab where `target` sits, keeping the order they end up
    /// in — the session remembers it.
    func move(_ id: UUID, onto target: UUID) {
        let current = documents.map(\.id)
        let wanted = TabSplit.reorder(ids: current, moving: id, onto: target)
        guard wanted != current else { return }

        let byID = Dictionary(uniqueKeysWithValues: documents.map { ($0.id, $0) })
        documents = wanted.compactMap { byID[$0] }
        persistSession()
    }

    func select(_ id: UUID) {
        guard selectedID != id else { return }
        selectedID = id
        persistSession()
    }

    // MARK: - Session

    /// Reopens last session's tabs. Runs before any open-file event, so files the
    /// user double-clicked land after the restored ones and end up selected.
    func restoreSession() {
        guard !didRestore else { return }
        didRestore = true

        let defaults = UserDefaults.standard
        let paths = defaults.stringArray(forKey: Self.openFilesKey) ?? []

        for path in paths where FileManager.default.fileExists(atPath: path) {
            // Silently skip unreadable files: a restore must never open an alert.
            let url = URL(fileURLWithPath: path)
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let document = MarkdownDocument()
            document.adopt(text: text, url: url)
            documents.append(document)
        }

        // Reversed, so the leftmost tab ends up at the top of the recents list.
        for document in documents.reversed() {
            if let url = document.url { noteRecent(url) }
        }

        if let last = defaults.string(forKey: Self.selectedFileKey),
           let match = documents.first(where: { $0.url?.path == last }) {
            selectedID = match.id
        } else {
            selectedID = documents.first?.id
        }
        persistSession()
    }

    func persistSession() {
        let defaults = UserDefaults.standard
        defaults.set(documents.compactMap { $0.url?.path }, forKey: Self.openFilesKey)
        defaults.set(selected?.url?.path, forKey: Self.selectedFileKey)
    }

    // MARK: - Recents

    /// Kept by hand in `UserDefaults`. `NSDocumentController.noteNewRecentDocumentURL`
    /// silently does nothing in an app that has no `NSDocument` subclass — it never
    /// writes the shared file list, so the recents menu stayed empty forever.
    private func noteRecent(_ url: URL) {
        var paths = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) ?? []
        paths.removeAll { $0 == url.path }
        paths.insert(url.path, at: 0)
        paths = Array(paths.prefix(maxRecent))
        UserDefaults.standard.set(paths, forKey: Self.recentFilesKey)

        // Still worth telling AppKit: it feeds the Dock's recent-items menu.
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        refreshRecentURLs()
    }

    func refreshRecentURLs() {
        let paths = UserDefaults.standard.stringArray(forKey: Self.recentFilesKey) ?? []
        recentURLs = paths.map { URL(fileURLWithPath: $0) }
    }

    func clearRecent() {
        UserDefaults.standard.removeObject(forKey: Self.recentFilesKey)
        NSDocumentController.shared.clearRecentDocuments(nil)
        refreshRecentURLs()
    }
}
