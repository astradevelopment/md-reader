# Update host — md.dmind.pro

Where the built app is published and where the app looks for newer builds. Kept
under the project's own domain rather than a host address, so the server can be
moved by repointing DNS without stranding copies already installed.

## Layout on the server

    /home/claude/md-reader-updates/     served by Caddy
        MD-Reader-<version>.dmg         one per release, older ones kept
        md-reader.dmg                   symlink to the current one — the link to hand out
    latest.dmg                      the same, kept so older links keep working
        appcast.json                    what the app reads
        index.html                      the download page
        icon.png

    /home/claude/md-reader-logs/        Caddy's access log for this host
    /home/claude/md-stats               downloads and update checks

`Caddyfile.md.dmind.pro` is the site block as it stands in `/etc/caddy/Caddyfile`.
Caddy issues and renews the certificate itself; there is no certbot.

## Publishing a new build

    ./build.sh release && ./make-dmg.sh
    scp "MD Reader.dmg" dmind:~/md-reader-updates/MD-Reader-<version>.dmg
    ssh dmind 'cat > ~/md-reader-updates/appcast.json' <<JSON
    {
      "version": "<version>",
      "url": "https://md.dmind.pro/MD-Reader-<version>.dmg",
      "notes": "<what changed>"
    }
    JSON

Then repoint the permanent link, which is what people are given:

    ssh dmind 'cd ~/md-reader-updates && ln -sfn MD-Reader-<version>.dmg md-reader.dmg && ln -sfn MD-Reader-<version>.dmg latest.dmg'

The app checks the feed quietly at launch, at most once a day. The page reads
the same feed, so its version number never needs editing.

## Links

    https://md.dmind.pro/             the page
    https://md.dmind.pro/md-reader.dmg  direct download, unchanged across releases

## Statistics

    ssh dmind '~/md-stats'        # everything in the logs
    ssh dmind '~/md-stats 7'      # the last seven days

Downloads are counted only where the file was actually delivered — a 200 or a
206 for a resumed fetch. Update checks are counted separately, since a check is
not a download.

## Two things that cost an hour

`caddy validate` runs as whoever invokes it, so validating a config whose log
path only Caddy can write fails on permissions — and worse, it creates the log
file owned by the wrong user, after which the real Caddy cannot write to it and
hangs mid-reload. The log therefore lives in a directory both can reach.

Caddy creates log files 0600 regardless of directory ACLs, so the file writer
needs an explicit `mode 644` for anything else to read them.
