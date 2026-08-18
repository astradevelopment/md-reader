import AppKit
import UniformTypeIdentifiers

/// Claiming the Markdown file association.
///
/// Launch Services resolves `.md` through whichever app it considers the best
/// handler, and Xcode re-asserts its own claim every time it is updated or
/// re-registered. An *explicit* user choice outranks every app's claim — and made
/// from inside MD Reader, the confirmation panel macOS raises is attributed to
/// MD Reader itself, so the request goes through.
@MainActor
enum DefaultHandler {
    private static let suppressKey = "defaultHandler.dontAsk"
    private static var didPromptThisLaunch = false

    static var markdownTypes: [UTType] {
        var types: [UTType] = []
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        for ext in ["md", "markdown", "mdown", "mkd", "mdtext"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }

    static var isDefault: Bool {
        guard let current = currentHandlerURL else { return false }
        return current.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }

    private static var currentHandlerURL: URL? {
        guard let markdown = UTType("net.daringfireball.markdown") else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: markdown)
    }

    private static var currentHandlerName: String? {
        guard let url = currentHandlerURL else { return nil }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Launch prompt

    /// Asks once per launch, and never again once the user says so.
    static func promptIfNeeded() {
        guard !didPromptThisLaunch else { return }
        guard !UserDefaults.standard.bool(forKey: suppressKey) else { return }
        guard !isDefault else { return }
        didPromptThisLaunch = true

        let alert = NSAlert()
        alert.messageText = "Open Markdown files in MD Reader?"
        if let holder = currentHandlerName {
            alert.informativeText =
                "Markdown files currently open in \(holder). MD Reader can take over .md, "
                + ".markdown and .mkd files."
        } else {
            alert.informativeText = "MD Reader can become the default app for .md, .markdown and .mkd files."
        }
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Make Default")
        alert.addButton(withTitle: "Not Now")
        alert.addButton(withTitle: "Don't Ask Again")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            makeDefault(announce: false)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(true, forKey: suppressKey)
        default:
            break
        }
    }

    // MARK: - Claiming

    static func makeDefault(announce: Bool = true) {
        let appURL = Bundle.main.bundleURL
        let types = markdownTypes
        guard !types.isEmpty else { return }

        Task { @MainActor in
            var failure: Error?
            for type in types {
                do {
                    try await NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: type)
                } catch {
                    // A UTI that doesn't exist on this machine isn't worth reporting;
                    // only remember the first real failure.
                    if failure == nil { failure = error }
                }
            }

            // Asking clears the suppression: the user has made a decision either way.
            UserDefaults.standard.set(true, forKey: suppressKey)

            let succeeded = isDefault
            guard announce || !succeeded else { return }
            report(succeeded: succeeded, failure: failure, appURL: appURL)
        }
    }

    private static func report(succeeded: Bool, failure: Error?, appURL: URL) {
        let alert = NSAlert()
        if succeeded {
            alert.messageText = "MD Reader now opens Markdown files"
            alert.alertStyle = .informational
            if !appURL.path.contains("/Applications/") {
                alert.informativeText =
                    "The app is running from \(appURL.deletingLastPathComponent().path). Launch Services "
                    + "keys the association to that exact path — move MD Reader.app and .md files go back "
                    + "to the previous app. Run install.sh to keep it in /Applications instead."
            } else {
                alert.informativeText = "Keep the app in /Applications so the association survives updates."
            }
        } else {
            alert.messageText = "Couldn't set MD Reader as the default"
            alert.informativeText = failure?.localizedDescription
                ?? "Launch Services turned the request down. Set it manually: right-click a .md file "
                + "in Finder, choose Get Info, pick MD Reader under “Open with”, then click “Change All…”."
            alert.alertStyle = .warning
        }
        alert.runModal()
    }
}
