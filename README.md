# MD Reader

A fast, native macOS reader for Markdown files. Not an editor — it opens `.md`
files and gets out of the way.

## Why

Large specs (tens of thousands of words, hundreds of table rows) are painful in a
general-purpose editor: no outline, no reading progress, no sense of where you
are. MD Reader is built around reading one long document at a time.

## Features

- **Outline sidebar** — every heading, nested, tracking your position as you scroll.
- **Tabs** — several documents in one window, with per-tab scroll position.
- **Session restore** — reopens the files you had open, and keeps a recents list.
- **Search** — full-text find with results and snippets in the sidebar.
- **Adjustable text size** — ⌘+ / ⌘− / ⌘0, remembered between launches.
- **Reading progress** in the toolbar.
- Liquid Glass toolbar controls on macOS 26, with a material fallback below it.

## Build

```bash
./build.sh release
```

Produces `MD Reader.app` next to the script. Requires macOS 15+ and a Swift 6
toolchain; `swift-markdown-ui` is fetched by SwiftPM.

## Install

```bash
./install.sh
```

Builds, copies the app to `/Applications` and registers it with Launch Services.
Then pick **File ▸ Make MD Reader the Default for Markdown…** once — an explicit
user choice outranks other apps' claims on `.md`, including Xcode's.

## Keyboard

| | |
|---|---|
| `⌘O` | Open files (multiple selection allowed) |
| `⌘W` | Close tab |
| `⇧⌘]` / `⇧⌘[` | Next / previous tab |
| `⌘F` | Find in document |
| `⌘G` / `⇧⌘G` | Next / previous match |
| `⌘+` / `⌘−` / `⌘0` | Bigger / smaller / actual text size |
| `⌃⌘S` | Toggle sidebar |

## Licence

MIT
