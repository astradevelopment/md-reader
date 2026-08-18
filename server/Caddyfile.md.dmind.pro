md.dmind.pro {
	root * /home/claude/md-reader-updates
	file_server
	encode gzip
	header /*.dmg Content-Type application/x-apple-diskimage
	header /appcast.json Cache-Control "no-cache"

	log {
		output file /home/claude/md-reader-logs/access.log {
			mode 644
			roll_size 20MiB
			roll_keep 6
		}
		format json
	}
}
