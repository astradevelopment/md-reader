import SwiftUI

/// What the window shows with no tabs open: the invitation to open a file, and
/// the last ten documents underneath it.
struct EmptyStateView: View {
    @ObservedObject var store: DocumentStore

    /// Recents survive the files themselves, so drop anything that has moved.
    private var recents: [URL] {
        store.recentURLs.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 32)

            VStack(spacing: 16) {
                Image(systemName: "doc.text")
                    .font(.system(size: 52, weight: .light))
                    .foregroundStyle(.tertiary)
                Text("Open a Markdown file")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text("Drag a .md file into this window, or use ⌘O.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                Button("Open…") { store.openPanel() }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .padding(.top, 4)
            }

            if !recents.isEmpty {
                recentSection
                    .padding(.top, 36)
            }

            Spacer(minLength: 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("RECENT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)

                Spacer()

                Button("Open All") {
                    store.openAll(recents)
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)

            ScrollView {
                VStack(spacing: 1) {
                    ForEach(recents, id: \.self) { url in
                        RecentRow(url: url) { store.open(url: url) }
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: 300)
        }
        .frame(width: 460)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: URL.self) { url, _ in
            guard let url else { return }
            DispatchQueue.main.async { store.open(url: url) }
        }
        return true
    }
}

private struct RecentRow: View {
    let url: URL
    let onOpen: () -> Void

    @State private var hovering = false

    private var location: String {
        (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "doc.text")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .frame(width: 16)

            Text(url.lastPathComponent)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(location)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(hovering ? 0.07 : 0))
        )
        .contentShape(RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .help(url.path)
    }
}
