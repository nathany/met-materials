#!/bin/sh
# Build and run a chapter:
#   ./run.sh 01-hello-metal [-define:CHALLENGE=true] [odin flags...]
#
# The port needs the `#simd` C-ABI fix (odin-lang/Odin#7010 / PR #7015),
# included in dev-2026-08. Use the PATH compiler by default; set ODIN to
# an explicit compiler path to test another version.
set -e
cd "$(dirname "$0")"

ODIN="${ODIN:-odin}"

chapter="$1"
if [ -z "$chapter" ] || [ ! -d "$chapter" ]; then
	echo "usage: ./run.sh <chapter-dir> [odin flags...]" >&2
	exit 1
fi
shift

"$ODIN" run "$chapter" -collection:common=common "$@"
