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
            localized: "You have \(currentVersion). The download opens in your browser; drag the new copy over the old one."
        )
        alert.alertStyle = .informational
        alert.addButton(withTitle: String(localized: "Download"))
        alert.addButton(withTitle: String(localized: "Later"))
        alert.addButton(withTitle: String(localized: "Skip This Version"))

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.download ?? release.page)
        case .alertThirdButtonReturn:
            UserDefaults.standard.set(release.version, forKey: skippedKey)
        default:
            break
        }
    }

    private static func report(title: String, body: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = body
        alert.alertStyle = .informational
        alert.runModal()
    }
}
