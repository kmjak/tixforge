#!/usr/bin/env bash
# The tixforge part of a Claude Code status line: the run of the current
# directory and its Status, e.g.
#   GT-000001 · plan:awaiting-approval
# The run is the one on the current branch, or else the run before Implement
# (no branch yet); with several of those, the first one and "(+<n>)".
# Prints nothing outside a tixforge run, so it can sit in any status line.
#
# Reads the status line JSON that Claude Code sends on stdin (cwd, or
# workspace.current_dir). Use it as the whole status line:
#   "statusLine": {"type": "command", "command": "bash <plugin>/scripts/statusline.sh"}
# or pass the same input on from your own status line script:
#   input=$(cat); tf=$(printf '%s' "$input" | bash <plugin>/scripts/statusline.sh)
set -u
# shellcheck source=SCRIPTDIR/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

input=$(cat)
cwd=$(printf '%s' "$input" | json_get cwd)
[ -n "$cwd" ] || cwd=$(printf '%s' "$input" | json_get workspace.current_dir)
[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

top=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null) || exit 0
[ -d "$(tf_dir "$top")" ] || exit 0
branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2> /dev/null || true)

runs=$(current_runs "$top" "$branch")
[ -n "$runs" ] || exit 0
n=$(printf '%s\n' "$runs" | wc -l)
first=$(printf '%s\n' "$runs" | head -1)
id=${first%/state.md}
id=${id##*/}
more=""
[ "$n" -gt 1 ] && more=" (+$((n - 1)))"
printf '%s · %s%s\n' "$id" "$(field "$first" Status)" "$more"
