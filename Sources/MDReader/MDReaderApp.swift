import SwiftUI

/// Only here to get a launch hook — SwiftUI's `App` has no equivalent of
/// `applicationDidFinishLaunching`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Before any open-file event arrives, so restored tabs sit behind the file the
    /// user actually double-clicked.
    func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { DocumentStore.shared.restoreSession() }
    }

    /// SwiftUI's `onOpenURL` only ever delivers one file; this receives the whole set.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated { DocumentStore.shared.openAll(urls) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            MainActor.assumeIsolated { DefaultHandler.promptIfNeeded() }
        }
    }
}

@main
struct MDReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = DocumentStore.shared

    var body: some Scene {
        // `Window`, not `WindowGroup`: tabs live inside one window, and a group
        // scene lets macOS restore several of them at once.
        Window("MD Reader", id: "reader") {
            ContentView(store: store)
                .frame(minWidth: 820, minHeight: 600)
                .onAppear {
                    NSWindow.allowsAutomaticWindowTabbing = false
                }
        }
        .defaultSize(width: 1100, height: 780)
        // The filename lives in the tab, so the toolbar shows no title of its own.
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") { store.openPanel() }
                    .keyboardShortcut("o", modifiers: .command)

                Menu("Open Recent") {
                    if store.recentURLs.isEmpty {
                        Text("No Recent Documents")
                    } else {
                        ForEach(store.recentURLs, id: \.self) { url in
                            Button(url.lastPathComponent) {
                                store.open(url: url)
                            }
                        }
                        Divider()
                        Button("Open All Recent") {
                            for url in store.recentURLs { store.open(url: url, persist: false) }
                            store.persistSession()
                        }
                        Button("Clear Menu") { store.clearRecent() }
                    }
                }

                Divider()

                Button("Close Tab") { store.closeSelectedOrWindow() }
                    .keyboardShortcut("w", modifiers: .command)

                Divider()

                Button("Make MD Reader the Default for Markdown…") {
                    DefaultHandler.makeDefault(announce: true)
                }
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") {
                    NotificationCenter.default.post(name: .mdrFind, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .mdrFindNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .mdrFindPrevious, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Toggle Sidebar") {
                    NSApp.keyWindow?.firstResponder?
                        .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])

                Divider()

                Button("Next Tab") { store.selectNext() }
                    .keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { store.selectPrevious() }
                    .keyboardShortcut("[", modifiers: [.command, .shift])

                Divider()

                Button("Bigger Text") { ReaderSettings.shared.increase() }
                    .keyboardShortcut("+", modifiers: .command)
                Button("Smaller Text") { ReaderSettings.shared.decrease() }
                    .keyboardShortcut("-", modifiers: .command)
                Button("Actual Size") { ReaderSettings.shared.reset() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}
