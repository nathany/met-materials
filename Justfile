# Recipes run from odin_port so the chapter asset paths remain valid.
set working-directory := "odin_port"
set positional-arguments

export ODIN := env("ODIN", "odin")

common_flags := "-collection:common=common -strict-style -warnings-as-errors"
sanitize_flags := "-debug -sanitize:address"

# List the available commands.
default:
    @just --list

# Run a chapter; additional arguments are passed to Odin unchanged.
run chapter *flags:
    "$ODIN" run "$@" {{ common_flags }}

# Check every implemented final/challenge variant without building a binary.
check: (check-chapter "01-hello-metal") (check-chapter "01-hello-metal" "-define:CHALLENGE=true") (check-chapter "02-3d-models" "-define:EXPORT_CONE=true") (check-chapter "02-3d-models") (check-chapter "02-3d-models" "-define:CHALLENGE=true")

# Check one chapter or package, with optional defines and other Odin flags.
check-chapter chapter *flags:
    @printf 'Checking %s\n' "$*"
    "$ODIN" check "$@" {{ common_flags }}

# Run a chapter with debug information and AddressSanitizer.
sanitize chapter *flags:
    "$ODIN" run "$@" {{ common_flags }} {{ sanitize_flags }}

# Run an Odin test package (the current demos do not contain unit tests).
test package *flags:
    "$ODIN" test "$@" {{ common_flags }}

# Run an Odin test package with debug information and AddressSanitizer.
test-sanitize package *flags:
    "$ODIN" test "$@" {{ common_flags }} {{ sanitize_flags }}
