#!/usr/bin/env bash
# Snapshot of tixforge for SKILL.md: injected with !`...` when tixforge starts, so
# the settings and the open runs are in context before anything is read.
# Always exits 0: a failing injected command would abort the skill.
set -u
# shellcheck source=SCRIPTDIR/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

top=$(tf_top)
conf=$(tf_config "$top")

# pending_lts: the .tixforge/LT-* folders still to move, one
# "<id>\t<run>\t<ticket>\t<reason>" line each (lt_info in lib.sh).
pending_lts() {
  local d info run rest
  for d in "$(tf_dir "$top")"/LT-*; do
    [ -d "$d" ] || continue
    info=$(lt_info "$d")
    run=${info%%	*}
    rest=${info#*	}
    lt_pending "$run" "${rest%%	*}" || continue
    printf '%s\t%s\n' "${d##*/}" "$info"
  done
}
# `project-status.sh lt`: only that list, for /tixforge:project update.
if [ "${1:-}" = lt ]; then
  pending_lts
  exit 0
fi

echo "- リポジトリ: ${top}"
if git -C "$top" rev-parse --git-dir > /dev/null 2>&1; then
  echo "- 現在のブランチ: $(git -C "$top" symbolic-ref --short -q HEAD 2> /dev/null || echo '(detached)')"
else
  echo "- git リポジトリではない"
fi

if [ -f "$conf" ]; then
  gates=$(cfg_list gates "$conf" | paste -sd, -)
  # An explicit empty list (no gate but the PR one) is not the same as a
  # missing key.
  [ -z "$gates" ] && cfg_has gates "$conf" && gates="[]（pr のみ）"
  echo "- 設定（.tixforge/config.yml）: language=$(cfg language "$conf")" \
    "tracker=$(cfg ticket.tracker "$conf")" \
    "base_branch=$(cfg repository.base_branch "$conf")" \
    "close_issues=$(cfg repository.close_issues "$conf")" \
    "review.required=$(cfg review.required "$conf")" \
    "gates=${gates:-（未設定）}"
else
  echo "- .tixforge/config.yml が無い（/tixforge:project init が未実行）"
fi

# What v2 left: local tickets (LT-), tracker: local and host: none. v3 keeps
# tickets in GitHub issues only, so they have to move first
# (/tixforge:project update). Without config.yml (before init) nothing is
# reported: init comes first.
lts=""
[ -f "$conf" ] && lts=$(pending_lts | cut -f1 | paste -sd' ' -)
[ -f "$conf" ] && [ "$(cfg ticket.tracker "$conf")" = local ] && lts="tracker: local${lts:+ / $lts}"
[ -n "$lts" ] && echo "- 移行が要る: ${lts}（v3 は LT を使えない。/tixforge:project update で issue に移す）"
[ -f "$conf" ] && [ "$(cfg repository.host "$conf")" = none ] \
  && echo "- 移行が要る: repository.host: none（v3 は GitHub が必須。GitHub のリポジトリを使うなら /tixforge:project update で移す。使わないなら tixforge v2 に留まる）"

open=""
while IFS="$RUN_SEP" read -r id s b _; do
  [ -n "$id" ] && is_open_status "$s" || continue
  open="${open}  - ${id}: Status ${s}、Branch ${b}
"
done << EOF
$(each_run "$top")
EOF
if [ -n "$open" ]; then
  echo "- 進行中の run:"
  printf '%s' "$open"
else
  echo "- 進行中の run: なし"
fi
exit 0
