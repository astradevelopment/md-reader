import Foundation

/// Renaming the file behind a tab, in the part of it that never touches the disk:
/// what the user typed, turned either into the URL to move to or into the reason
/// it cannot be one.
///
/// A separate type because the interesting cases are the ones you cannot see:
/// a name that differs only in case is a legal rename that a naive
/// "does something already exist there?" check refuses.
enum FileRename {
    enum Problem: Error, Equatable {
        /// Nothing but spaces.
        case empty
        /// `/` is the path separator, `:` is what Finder still shows as one.
        case separator
        /// A leading dot hides the file — never what someone renaming a tab meant.
        case hidden
        /// Typed back the name it already has.
        case unchanged
        /// Another file is already sitting there.
        case taken
    }

    /// The part offered for editing. Finder puts the extension outside the
    /// selection, so the reader keeps it out of the field altogether.
    static func baseName(of url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
    }

    /// The extension with its dot, shown beside the field and glued back on
    /// commit — `".md"`, or nothing at all for a file without one.
    static func suffix(of url: URL) -> String {
        let ext = url.pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    /// `existing` answers whether a path is occupied: the file manager in the
    /// app, a set of paths in the tests.
    static func target(
        for url: URL,
        typed: String,
        existing: (String) -> Bool
    ) -> Result<URL, Problem> {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty else { return .failure(.empty) }
        guard !name.contains("/"), !name.contains(":") else { return .failure(.separator) }
        guard !name.hasPrefix(".") else { return .failure(.hidden) }

        // The field holds the name without the extension, but people type what
        // they know the file is called. "notes.md" for a .md file means the file
        // keeps its extension, not that it grows a second one.
        let tail = suffix(of: url)
        var stem = name
        if !tail.isEmpty,
           stem.count > tail.count,
           stem.lowercased().hasSuffix(tail.lowercased()) {
            stem.removeLast(tail.count)
        }

        guard !stem.isEmpty else { return .failure(Problem.empty) }
        guard stem != baseName(of: url) else { return .failure(Problem.unchanged) }

        let target = url.deletingLastPathComponent().appendingPathComponent(stem + tail)

        // "notes" → "Notes" is a rename people make, and on the case-insensitive
        // volume macOS ships with, the file it would land on is the file itself.
        // Asking the file system there always answers "taken".
        let sameFile = target.path.compare(url.path, options: .caseInsensitive) == .orderedSame
        guard sameFile || !existing(target.path) else { return .failure(Problem.taken) }

        return .success(target)
    }
}
