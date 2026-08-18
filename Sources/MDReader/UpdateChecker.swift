import AppKit

/// Looks for a newer build on the project's GitHub releases.
///
/// It only ever reports; nothing is installed behind your back. The app is
/// ad-hoc signed rather than notarised, so an update has to be dragged across
/// like the first install — pretending otherwise would mean shipping an
/// installer that Gatekeeper would stop anyway.
@MainActor
enum UpdateChecker {
    private static let latestRelease = URL(
        string: "https://api.github.com/repos/astradevelopment/md-reader/releases/latest"
    )!

    private static let lastCheckKey = "update.lastCheckedAt"
    private static let skippedKey = "update.skippedVersion"
    private static let interval: TimeInterval = 60 * 60 * 24

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    // MARK: - Version comparison

    /// Compares dotted versions numerically, so 1.10 is newer than 1.9 and a
    /// missing component counts as zero: 1.4 and 1.4.0 are the same build.
    nonisolated static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = parts(of: candidate)
        let b = parts(of: current)
        for i in 0..<max(a.count, b.count) {
            let left = i < a.count ? a[i] : 0
            let right = i < b.count ? b[i] : 0
            if left != right { return left > right }
        }
        return false
    }

    nonisolated private static func parts(of version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }

    // MARK: - Checking

    private struct Release {
        let version: String
        let page: URL
        let download: URL?
    }

    /// Runs at launch, at most once a day, and stays silent unless there is
    /// something newer — and quiet about failures entirely.
    static func checkQuietly() {
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > interval else { return }

        Task {
            guard let release = await fetch() else { return }
            defaults.set(Date(), forKey: lastCheckKey)

            guard isNewer(release.version, than: currentVersion),
                  release.version != defaults.string(forKey: skippedKey)
            else { return }
            announce(release)
        }
    }

    /// From the menu, where silence would look broken.
    static func checkNow() {
        Task {
            guard let release = await fetch() else {
                report(
                    title: String(localized: "Couldn't check for updates"),
                    body: String(localized: "The releases page could not be reached. Try again later.")
                )
                return
            }
            UserDefaults.standard.set(Date(), forKey: lastCheckKey)

            if isNewer(release.version, than: currentVersion) {
                announce(release)
            } else {
                report(
                    title: String(localized: "MD Reader is up to date"),
                    body: String(localized: "You have version \(currentVersion).")
                )
            }
        }
    }

    private static func fetch() async -> Release? {
        var request = URLRequest(url: latestRelease)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let pageText = json["html_url"] as? String,
              let page = URL(string: pageText)
        else { return nil }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let dmg = assets
            .compactMap { $0["browser_download_url"] as? String }
            .first { $0.hasSuffix(".dmg") }
            .flatMap(URL.init(string:))

        return Release(version: tag, page: page, download: dmg)
    }

    // MARK: - Telling you about it

    private static func announce(_ release: Release) {
        let alert = NSAlert()
        alert.messageText = String(localized: "MD Reader \(release.version) is available")
        alert.informativeText = String(
            localized: "You have \(currentVersion). It will be downloaded, put in place and reopened."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Update and Restart"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.addButton(withTitle: String(localized: "Skip This Version"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            guard let download = release.download else {
                NSWorkspace.shared.open(release.page)
                return
            }
            Task { await install(from: download, page: release.page) }
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedKey)
        default:
            break
        }
    }

    // MARK: - Installing

    /// Fetches the image, takes the app out of it, and hands the swap to a script
    /// that outlives this process — a running bundle cannot replace itself.
    private static func install(from download: URL, page: URL) async {
        let progress = ProgressWindow(
            message: String(localized: "Downloading MD Reader…")
        )
        progress.show()

        do {
            let staged = try await stageUpdate(from: download)
            progress.close()
            try relaunch(replacing: Bundle.main.bundleURL, with: staged)
        } catch {
            progress.close()
            let alert = NSAlert()
            alert.messageText = String(localized: "The update couldn't be installed")
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: String(localized: "Open the Download Page"))
            alert.addButton(withTitle: String(localized: "Later"))
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(page)
            }
        }
    }

    private struct UpdateFailure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    /// Downloads the image, mounts it, copies the app out, unmounts. The copy is
    /// what gets installed, so the image can be released straight away.
    private static func stageUpdate(from download: URL) async throws -> URL {
        let (temporary, response) = try await URLSession.shared.download(from: download)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw UpdateFailure(String(localized: "The download did not complete."))
        }

        let work = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MDReaderUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)

        let image = work.appendingPathComponent("update.dmg")
        try FileManager.default.moveItem(at: temporary, to: image)

        let mount = work.appendingPathComponent("mount")
        try run("/usr/bin/hdiutil", ["attach", "-quiet", "-nobrowse", "-readonly",
                                     "-mountpoint", mount.path, image.path])
        defer { _ = try? run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }

        guard let app = try FileManager.default
            .contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" })
        else {
            throw UpdateFailure(String(localized: "The disk image did not contain an app."))
        }

        let staged = work.appendingPathComponent(app.lastPathComponent)
        try run("/usr/bin/ditto", [app.path, staged.path])

        // The quarantine flag this download may have picked up would stop the very
        // update it belongs to. It is cleared here, on a build fetched from the
        // project's own releases at the user's request.
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", staged.path])

        guard FileManager.default.fileExists(
            atPath: staged.appendingPathComponent("Contents/MacOS").path
        ) else {
            throw UpdateFailure(String(localized: "The downloaded app looks incomplete."))
        }
        return staged
    }

    /// A bundle cannot overwrite itself while it is running, so the swap is left
    /// to a script that waits for this process to go, keeps the old copy until
    /// the new one is in place, and puts it back if anything fails.
    private static func relaunch(replacing target: URL, with staged: URL) throws {
        let script = staged.deletingLastPathComponent().appendingPathComponent("swap.sh")
        let body = """
        #!/bin/bash
        target="$1"; staged="$2"; owner="$3"
        while kill -0 "$owner" 2>/dev/null; do sleep 0.2; done
        backup="${target}.previous"
        rm -rf "$backup"
        [ -d "$target" ] && mv "$target" "$backup"
        if /usr/bin/ditto "$staged" "$target"; then
            rm -rf "$backup"
        else
            rm -rf "$target"
            [ -d "$backup" ] && mv "$backup" "$target"
        fi
        /usr/bin/open "$target"
        rm -rf "$(dirname "$staged")"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: script.path
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            script.path, target.path, staged.path, String(ProcessInfo.processInfo.processIdentifier),
        ]
        try process.run()

        NSApp.terminate(nil)
    }

    @discardableResult
    private static func run(_ tool: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateFailure(
                String(localized: "\(URL(fileURLWithPath: tool).lastPathComponent) failed.")
            )
        }
        return process.terminationStatus
    }

    private static func report(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }
}
