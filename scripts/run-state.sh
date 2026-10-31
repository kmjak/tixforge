#!/usr/bin/env bash
# The tixforge run state file, .tixforge/<id>/state.md: creates it and reads
# or writes its header table. Sections are written by Claude with Edit; this
# script owns the header so Status and Updated never drift apart. The ticket
# is .tixforge/<id>/ticket.md and a GT id carries its issue number, so the
# header does not repeat them.
#
#   run-state.sh init <id>                   create state.md (Status research:in-progress)
#   run-state.sh get <id> [field]            print a header field (default Status)
#   run-state.sh set <id> <field> <value>    set Status / Branch / Base; also sets Updated
#   run-state.sh list                        "<id>\t<Status>\t<Branch>" for every run
#   run-state.sh rewind <id> <phase> [--keep-log] [--reason <text>]
#                                            go back to research / approach / plan / implement
#   run-state.sh migrate [--check] <id>      bring state.md to the current format
#
# The Format row of the header is the version of the file's layout (none:
# 2, what v2 wrote). init writes the current one; migrate moves an older
# file up, and --check only prints what it would change (nothing when the
# file is current). Only init and migrate write Format. Raise STATE_FORMAT,
# and teach migrate the step, whenever a change makes the old layout wrong.
#
# rewind moves the sections of the target phase and every later phase into
# .tixforge/<id>/history/<time>.md (so they are not read as approved any
# more, but can be looked up), leaves them empty in state.md, puts
# "> 巻き戻し（<time>）：<reason>" under the target section, and sets Status
# to <phase>:in-progress. Going back to implement keeps the Implementation
# Log (the commits are still there) and moves Review and PR. --keep-log
# keeps the Implementation Log too when going back further (the work goes
# on on the same branch). Prints the history file. Refuses a done or
# canceled run, and a phase after the current one (rewinding to the current
# phase is fine: plan:awaiting-approval -> plan). Only the six fixed
# headings start a section (lib.sh), so "## " lines quoted in a fence stay
# with their section.
#
# Exit: 0 ok, 1 no such run, 2 usage or invalid value (a phase after the
#       current one, too), 3 run already exists, 4 the run is done or canceled,
#       5 the file is in a newer format than this tixforge knows.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
  grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
  exit 2
}

top=$(tf_top)
sfile() { state_file "$1" "$top"; }

valid_status() {
  case "$1" in
    research:in-progress | research:awaiting-approval) ;;
    approach:in-progress | approach:awaiting-approval) ;;
    plan:in-progress | plan:awaiting-approval) ;;
    implement:in-progress | implement:awaiting-approval) ;;
    review:in-progress | review:awaiting-approval) ;;
    pr:in-progress | pr:awaiting-approval | pr:awaiting-review | pr:ready-to-merge) ;;
    done | canceled) ;;
    *) return 1 ;;
  esac
}

# put <file> <field> <value>: rewrite one row of the header table.
put() {
  local tmp
  tmp=$(mktemp) || exit 1
  awk -F'|' -v k="$2" -v v="$3" '
    { key = $2; gsub(/^[ \t]+|[ \t]+$/, "", key) }
    !done && key == k { printf "| %-7s | %-34s |\n", k, v; done = 1; next }
    { print }
    END { if (!done) exit 1 }' "$1" > "$tmp" || {
    rm -f "$tmp"
    echo "no field $2 in $1" >&2
    exit 2
  }
  cat "$tmp" > "$1"
  rm -f "$tmp"
}

STATE_FORMAT=3

# The comments v2 wrote under each empty section (format 2). migrate removes
# exactly these lines; any other comment is the user's.
V2_PLACEHOLDERS='<!-- Phase 1: organized understanding of the ticket + relevant context -->
<!-- Phase 2: chosen implementation approach and key design decisions -->
<!-- Phase 3: branch, base, acceptance criteria -> verification table, ordered commits -->
<!-- Phase 4: commits, verification results, manual checks, notable decisions -->
<!-- Phase 5: reviewer findings as rounds, with recommendations and decisions -->
<!-- Phase 6: title, target branch, URL, review outcome -->'

# format_of <file>: the Format row, or 2 when there is none.
format_of() {
  local v
  v=$(field "$1" Format)
  printf '%s\n' "${v:-2}"
}

# v2_step <file> <count|write>: count the v2 placeholders outside fences, or
# print the file without them and with a Format row after the header table.
v2_step() {
  RS_PH=$V2_PLACEHOLDERS awk -v mode="$2" -v fmt="$STATE_FORMAT" "$_section_awk"'
    BEGIN { n = split(ENVIRON["RS_PH"], p, "\n"); for (i = 1; i <= n; i++) ph[p[i]] = 1 }
    {
      line = $0; sub(/\r$/, "", line)
      heading_index($0)
      if (_fence == "" && line in ph) { found++; next }
      if (mode == "write" && !added && intable && line !~ /^\|/) { printf "| %-7s | %-34s |\n", "Format", fmt; added = 1 }
      if (line ~ /^\|/) intable = 1
      if (mode == "write") print
    }
    END {
      if (mode == "count") print found + 0
      else if (!added) printf "| %-7s | %-34s |\n", "Format", fmt
    }' "$1"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  init)
    [ $# -eq 1 ] || usage
    is_ticket_id "$1" || {
      echo "not a ticket id: $1" >&2
      exit 2
    }
    f=$(sfile "$1")
    [ -e "$f" ] && {
      echo "run already exists: ${f#$top/}" >&2
      exit 3
    }
    ensure_workspace "$top"
    mkdir -p "$(dirname "$f")"
    {
      printf '# Run: %s\n\n' "$1"
      printf '| %-7s | %-34s |\n' Field Value
      printf '|---------|------------------------------------|\n'
      printf '| %-7s | %-34s |\n' Status research:in-progress \
        Branch — Base — Updated "$(tf_now)" Format "$STATE_FORMAT"
      old_ifs=$IFS
      IFS='|'
      for sec in $STATE_SECTIONS; do printf '\n## %s\n' "$sec"; done
      IFS=$old_ifs
    } > "$f"
    printf '%s\n' "${f#$top/}"
    ;;
  get)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    f=$(sfile "$1")
    [ -f "$f" ] || {
      echo "no run: $1" >&2
      exit 1
    }
    field "$f" "${2:-Status}"
    ;;
  set)
    [ $# -eq 3 ] || usage
    f=$(sfile "$1")
    [ -f "$f" ] || {
      echo "no run: $1" >&2
      exit 1
    }
    case $2 in
      Status) valid_status "$3" || {
        echo "invalid Status: $3" >&2
        exit 2
      } ;;
      Branch | Base) ;;
      *)
        echo "field not settable: $2 (Status, Branch, Base)" >&2
        exit 2
        ;;
    esac
    put "$f" "$2" "$3"
    put "$f" Updated "$(tf_now)"
    field "$f" "$2"
    ;;
  rewind)
    [ $# -ge 2 ] || usage
    id=$1 phase=$2 keep="" reason=""
    shift 2
    while [ $# -gt 0 ]; do
      case $1 in
        --keep-log)
          keep=1
          shift
          ;;
        --reason)
          [ $# -ge 2 ] || usage
          reason=$2
          shift 2
          ;;
        *) usage ;;
      esac
    done
    f=$(sfile "$id")
    [ -f "$f" ] || {
      echo "no run: $id" >&2
      exit 1
    }
    before=$(field "$f" Status)
    case $before in done | canceled)
      echo "run $id is $before: it cannot be rewound" >&2
      exit 4
      ;;
    esac
    # Phases in order; target is the section that gets the note.
    case $phase in
      research)
        from=1
        target=1
        ;;
      approach)
        from=2
        target=2
        ;;
      plan)
        from=3
        target=3
        ;;
      implement)
        from=5
        target=4
        keep=1
        ;;
      *)
        echo "cannot rewind to: $phase (research, approach, plan, implement)" >&2
        exit 2
        ;;
    esac
    case ${before%%:*} in
      research) at=1 ;; approach) at=2 ;; plan) at=3 ;; implement) at=4 ;; review) at=5 ;; *) at=6 ;;
    esac
    if [ "$target" -gt "$at" ]; then
      echo "cannot rewind to $phase: run $id is at $before (rewind goes back, not forward)" >&2
      exit 2
    fi
    now=$(tf_now)
    # Two rewinds in the same second must not share a file (awk truncates it).
    stamp=$(date '+%Y%m%d-%H%M%S')
    hist="$(dirname "$f")/history/$stamp.md"
    i=2
    while [ -e "$hist" ]; do
      hist="$(dirname "$f")/history/$stamp-$i.md"
      i=$((i + 1))
    done
    mkdir -p "$(dirname "$hist")"
    tmp=$(mktemp) || exit 1
    # Section n (1-based in STATE_SECTIONS) moves when n >= from, except the
    # Implementation Log (4) with --keep-log. Text goes in through ENVIRON:
    # awk -v would turn the \t of C:\temp into a tab.
    RW_HIST=$hist RW_HEAD="# Rewound to $phase ($now)" RW_WAS="Status before: $before" \
      RW_WHY=$reason RW_NOTE="> 巻き戻し（${now}）：${reason}" \
      awk -v from="$from" -v keep="$keep" -v target="$target" \
      "$_section_awk"'
      BEGIN {
        hist = ENVIRON["RW_HIST"]; why = ENVIRON["RW_WHY"]
        print ENVIRON["RW_HEAD"] > hist; print "" > hist; print ENVIRON["RW_WAS"] > hist
        if (why != "") print "Reason: " why > hist
      }
      { cur = heading_index($0) }
      cur {
        moving = cur >= from && !(cur == 4 && keep != "")
        print
        if (cur == target + 0 && why != "") print ENVIRON["RW_NOTE"]
        if (moving) { print "" > hist; print $0 > hist; print "" }
        next
      }
      moving { print > hist; next }
      { print }' "$f" > "$tmp" || {
      rm -f "$tmp"
      exit 1
    }
    cat "$tmp" > "$f"
    rm -f "$tmp"
    put "$f" Status "$phase:in-progress"
    put "$f" Updated "$now"
    printf '%s\n' "${hist#$top/}"
    ;;
  migrate)
    check=""
    [ "${1:-}" = --check ] && check=1 && shift
    [ $# -eq 1 ] || usage
    f=$(sfile "$1")
    [ -f "$f" ] || {
      echo "no run: $1" >&2
      exit 1
    }
    from=$(format_of "$f")
    case $from in '' | *[!0-9]*)
      echo "invalid Format in ${f#$top/}: $from" >&2
      exit 2
      ;;
    esac
    [ "$from" -gt "$STATE_FORMAT" ] && {
      echo "${f#$top/} is format $from, newer than this tixforge ($STATE_FORMAT): update the plugin" >&2
      exit 5
    }
    [ "$from" -eq "$STATE_FORMAT" ] && exit 0
    # Format 2 -> 3 is the only step so far.
    if [ -n "$check" ]; then
      printf 'format %s -> %s\n' "$from" "$STATE_FORMAT"
      printf -- '- remove the placeholder comments (%s)\n' "$(v2_step "$f" count)"
      printf -- '- add the Format row\n'
      exit 0
    fi
    tmp=$(mktemp) || exit 1
    v2_step "$f" write > "$tmp" || {
      rm -f "$tmp"
      exit 1
    }
    cat "$tmp" > "$f"
    rm -f "$tmp"
    printf 'format %s -> %s: %s\n' "$from" "$STATE_FORMAT" "${f#$top/}"
    ;;
  list)
    for f in "$(tf_dir "$top")"/*/state.md; do
      [ -f "$f" ] || continue
      id=${f%/state.md}
      id=${id##*/}
      printf '%s\t%s\t%s\n' "$id" "$(field "$f" Status)" "$(field "$f" Branch)"
    done
    ;;
  *) usage ;;
esac
