#!/usr/bin/env bash
# Run the Spotless Kotlin lint check (or apply fixes) from the repository root.
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: run-spotless-check.sh [--apply] [--module <name>] [-h|--help]

  --apply           Run spotlessApply instead of spotlessCheck
  --module <name>   Limit to one Gradle module (for example shop-service)
  -h, --help        Show this help

Examples:
  scripts/run-spotless-check.sh
  scripts/run-spotless-check.sh --apply
  scripts/run-spotless-check.sh --module shop-service
EOF
}

mode="check"
module=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --apply)
            mode="apply"
            shift
            ;;
        --module)
            if [[ $# -lt 2 || -z "${2:-}" ]]; then
                echo "error: --module requires a module name" >&2
                usage >&2
                exit 2
            fi
            module="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$root"

if [[ ! -x ./gradlew ]]; then
    echo "error: ./gradlew not found or not executable in $root" >&2
    exit 1
fi

case "$mode" in
    check) task="spotlessCheck" ;;
    apply) task="spotlessApply" ;;
esac

if [[ -n "$module" ]]; then
    module="${module#:}"
    task=":${module}:${task}"
fi

echo "Running ./gradlew ${task}"
./gradlew "$task"

if [[ "$mode" == "apply" ]]; then
    echo
    echo "Working tree changes after spotlessApply:"
    git status --short
fi
