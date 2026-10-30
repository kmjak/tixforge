#!/usr/bin/env bash
# SessionStart hook for tixforge (matcher: compact|resume). After the
# conversation is compacted, the skill's SKILL.md is re-attached but a mode
# file read with Read (skills/dev/run.md) may survive only as a summary. When a
# tixforge run is in progress here, this prints a reminder that Claude Code
# adds to the context: which run, its Status, and what to re-read.
# Prints nothing (and changes nothing) anywhere else.
set -u
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"

input=$(cat)
cwd=$(printf '%s' "$input" | sed -n 's/.*"cwd"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
[ -n "$cwd" ] && [ -d "$cwd" ] && cd "$cwd"

top=$(git rev-parse --show-toplevel 2> /dev/null) || exit 0
branch=$(git symbolic-ref --short -q HEAD 2> /dev/null || true)

run=""
early=""
for f in "$(tf_dir "$top")"/*/state.md; do
  [ -f "$f" ] || continue
  st=$(field "$f" Status)
  is_open_status "$st" || continue
  if [ -n "$branch" ] && [ "$(field "$f" Branch)" = "$branch" ]; then
    run=$f
    break
  fi
  case "$st" in research:* | approach:* | plan:*) early="${early}${early:+
}$f" ;; esac
done
# Not on a run's branch: a run before Implement has no branch yet. Remind
# of it when it is the only one; with several, the user says which.
if [ -z "$run" ] && [ -n "$early" ]; then
  [ "$(printf '%s\n' "$early" | wc -l)" -eq 1 ] && run=$early
fi
if [ -z "$run" ] && [ -n "$early" ]; then
  ids=$(printf '%s\n' "$early" | while IFS= read -r f; do
    d=${f%/state.md}
    printf '%s ' "${d##*/}"
  done)
  cat << EOF
[tixforge] この作業ディレクトリには Plan の承認前の run が複数あります（${ids% }）。会話が要約・再開されたため、どの run を進めていたかをユーザーに確認し、その run の状態ファイル（.tixforge/<id>/state.md）と次を Read し直してください:
- ${here%/scripts}/skills/dev/run.md
- ${here%/scripts}/references/common.md
EOF
  exit 0
fi
[ -n "$run" ] || exit 0

id=${run%/state.md}
id=${id##*/}
st=$(field "$run" Status)
extra=""
case "$st" in pr:*) extra="
- ${here%/scripts}/skills/dev/pr.md" ;; esac
cat << EOF
[tixforge] この作業ディレクトリでは /tixforge:dev の run ${id} が進行中です（Status: $(field "$run" Status)、Branch: $(field "$run" Branch)）。
会話が要約・再開されたため、手順書の細部が失われている可能性があります。tixforge の作業を続ける前に、次を Read し直してください:
- ${here%/scripts}/skills/dev/run.md${extra}
- ${here%/scripts}/references/common.md
- ${run#$top/}
EOF
exit 0
