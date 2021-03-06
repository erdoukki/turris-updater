#!/bin/sh
sed -n 's/^Alternatives://p' /usr/lib/opkg/info/*.control | \
	tr , '\n' | \
	sed 's/^\ \([^:]*\):\([^:]*\):/\2:\1:/' | \
	sort | \
	while IFS=: read TRG PRIO SRC; do
		ln -sf $SRC $TRG
	done
