#!/bin/sh
# Build and run a chapter:
#   ./run.sh 01-hello-metal [-define:CHALLENGE=true] [odin flags...]
#
# The port needs the `#simd` C-ABI fix (odin-lang/Odin#7010 / PR #7015),
# included in dev-2026-08. Until Homebrew catches up, this defaults to the
# locally built compiler; override with ODIN=odin once your PATH compiler is
# new enough.
set -e
cd "$(dirname "$0")"

ODIN="${ODIN:-$HOME/src/github.com/odin-lang/Odin/odin}"

chapter="$1"
if [ -z "$chapter" ] || [ ! -d "$chapter" ]; then
	echo "usage: ./run.sh <chapter-dir> [odin flags...]" >&2
	exit 1
fi
shift

"$ODIN" run "$chapter" -collection:common=common "$@"
