#!/bin/sh
# Compiles the Objective-C shim (see shim/sphere_shim.m for why it exists),
# then builds and runs the Odin program. Extra arguments pass through to
# `odin run`, e.g.:
#   ./build.sh -define:CHALLENGE=true
set -e
cd "$(dirname "$0")"
clang -c shim/sphere_shim.m -o shim/sphere_shim.o
odin run . "$@"
