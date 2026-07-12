#!/bin/sh
# Build and run a chapter:
#   ./run.sh 01-hello-metal [-define:CHALLENGE=true] [odin flags...]
#
# Compiles the Objective-C shims in common/ (only needed because Odin's
# #simd types don't follow the C vector ABI — see Metal-odin-port-plan.md
# §3.10), then runs the chapter package with the `common` collection mapped
# so chapters can `import "common:modelio"`.
set -e
cd "$(dirname "$0")"

chapter="$1"
if [ -z "$chapter" ] || [ ! -d "$chapter" ]; then
	echo "usage: ./run.sh <chapter-dir> [odin flags...]" >&2
	exit 1
fi
shift

for shim in common/*/*.m; do
	obj="${shim%.m}.o"
	if [ ! -f "$obj" ] || [ "$shim" -nt "$obj" ]; then
		clang -c "$shim" -o "$obj"
	fi
done

odin run "$chapter" -collection:common=common "$@"
