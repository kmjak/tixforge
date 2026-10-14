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
#       current one, too), 3 run already exists, 4 the run is done or canceled.
set -uo pipefail
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() { grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2; exit 2; }

top=$(flow_top)
sfile() { state_file "$1" "$top"; }

valid_status() {
  case "$1" in
    research:in-progress|research:awaiting-approval) ;;
    approach:in-progress|approach:awaiting-approval) ;;
    plan:in-progress|plan:awaiting-approval) ;;
    implement:in-progress|implement:awaiting-approval) ;;
    review:in-progress|review:awaiting-approval) ;;
    pr:in-progress|pr:awaiting-approval|pr:awaiting-review|pr:ready-to-merge) ;;
    done|canceled) ;;
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
    END { if (!done) exit 1 }' "$1" > "$tmp" || { rm -f "$tmp"; echo "no field $2 in $1" >&2; exit 2; }
  cat "$tmp" > "$1"; rm -f "$tmp"
}

# The empty placeholders of the sections (STATE_SECTIONS in lib.sh).
placeholder() {
  case "$1" in
    Research) echo '<!-- Phase 1: organized understanding of the ticket + relevant context -->' ;;
    Approach) echo '<!-- Phase 2: chosen implementation approach and key design decisions -->' ;;
    Plan) echo '<!-- Phase 3: branch, base, acceptance criteria -> verification table, ordered commits -->' ;;
    'Implementation Log') echo '<!-- Phase 4: commits, verification results, manual checks, notable decisions -->' ;;
    Review) echo '<!-- Phase 5: reviewer findings as rounds, with recommendations and decisions -->' ;;
    PR) echo '<!-- Phase 6: title, target branch, URL, review outcome -->' ;;
  esac
}

cmd=${1:-}; [ $# -gt 0 ] && shift
case $cmd in
  init)
    [ $# -eq 1 ] || usage
    is_ticket_id "$1" || { echo "not a ticket id: $1" >&2; exit 2; }
    f=$(sfile "$1")
    [ -e "$f" ] && { echo "run already exists: ${f#$top/}" >&2; exit 3; }
    ensure_workspace "$top"
    mkdir -p "$(dirname "$f")"
    {
      printf '# Run: %s\n\n' "$1"
      printf '| %-7s | %-34s |\n' Field Value
      printf '|---------|------------------------------------|\n'
      printf '| %-7s | %-34s |\n' Status research:in-progress \
        Branch — Base — Updated "$(flow_now)"
      cat <<'EOF'

## Research
<!-- Phase 1: organized understanding of the ticket + relevant context -->

## Approach
<!-- Phase 2: chosen implementation approach and key design decisions -->

## Plan
<!-- Phase 3: branch, base, acceptance criteria -> verification table, ordered commits -->

## Implementation Log
<!-- Phase 4: commits, verification results, manual checks, notable decisions -->

## Review
<!-- Phase 5: reviewer findings as rounds, with recommendations and decisions -->

## PR
<!-- Phase 6: title, target branch, URL, review outcome -->
EOF
    } > "$f"
    printf '%s\n' "${f#$top/}"
    ;;
  get)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    f=$(sfile "$1"); [ -f "$f" ] || { echo "no run: $1" >&2; exit 1; }
    field "$f" "${2:-Status}"
    ;;
  set)
    [ $# -eq 3 ] || usage
    f=$(sfile "$1"); [ -f "$f" ] || { echo "no run: $1" >&2; exit 1; }
    case $2 in
      Status) valid_status "$3" || { echo "invalid Status: $3" >&2; exit 2; } ;;
      Branch|Base) ;;
      *) echo "field not settable: $2 (Status, Branch, Base)" >&2; exit 2 ;;
    esac
    put "$f" "$2" "$3"
    put "$f" Updated "$(flow_now)"
    field "$f" "$2"
    ;;
  rewind)
    [ $# -ge 2 ] || usage
    id=$1 phase=$2 keep="" reason=""; shift 2
    while [ $# -gt 0 ]; do
      case $1 in
        --keep-log) keep=1; shift ;;
        --reason) [ $# -ge 2 ] || usage; reason=$2; shift 2 ;;
        *) usage ;;
      esac
    done
    f=$(sfile "$id"); [ -f "$f" ] || { echo "no run: $id" >&2; exit 1; }
    before=$(field "$f" Status)
    case $before in done|canceled) echo "run $id is $before: it cannot be rewound" >&2; exit 4 ;; esac
    # Phases in order; target is the section that gets the note.
    case $phase in
      research) from=1; target=1 ;;
      approach) from=2; target=2 ;;
      plan) from=3; target=3 ;;
      implement) from=5; target=4; keep=1 ;;
      *) echo "cannot rewind to: $phase (research, approach, plan, implement)" >&2; exit 2 ;;
    esac
    case ${before%%:*} in
      research) at=1 ;; approach) at=2 ;; plan) at=3 ;; implement) at=4 ;; review) at=5 ;; *) at=6 ;;
    esac
    if [ "$target" -gt "$at" ]; then
      echo "cannot rewind to $phase: run $id is at $before (rewind goes back, not forward)" >&2; exit 2
    fi
    now=$(flow_now)
    # Two rewinds in the same second must not share a file (awk truncates it).
    stamp=$(date '+%Y%m%d-%H%M%S'); hist="$(dirname "$f")/history/$stamp.md"; i=2
    while [ -e "$hist" ]; do hist="$(dirname "$f")/history/$stamp-$i.md"; i=$((i + 1)); done
    mkdir -p "$(dirname "$hist")"
    tmp=$(mktemp) || exit 1
    # Section n (1-based in STATE_SECTIONS) moves when n >= from, except the
    # Implementation Log (4) with --keep-log. Text goes in through ENVIRON:
    # awk -v would turn the \t of C:\temp into a tab.
    RW_HIST=$hist RW_HEAD="# Rewound to $phase ($now)" RW_WAS="Status before: $before" \
    RW_WHY=$reason RW_NOTE="> 巻き戻し（${now}）：${reason}" \
    awk -v from="$from" -v keep="$keep" -v target="$target" \
        -v ph1="$(placeholder Research)" -v ph2="$(placeholder Approach)" -v ph3="$(placeholder Plan)" \
        -v ph4="$(placeholder 'Implementation Log')" -v ph5="$(placeholder Review)" -v ph6="$(placeholder PR)" "$_section_awk"'
      BEGIN {
        hist = ENVIRON["RW_HIST"]; why = ENVIRON["RW_WHY"]
        ph[1] = ph1; ph[2] = ph2; ph[3] = ph3; ph[4] = ph4; ph[5] = ph5; ph[6] = ph6
        print ENVIRON["RW_HEAD"] > hist; print "" > hist; print ENVIRON["RW_WAS"] > hist
        if (why != "") print "Reason: " why > hist
      }
      { cur = heading_index($0) }
      cur {
        moving = cur >= from && !(cur == 4 && keep != "")
        print
        if (cur == target + 0 && why != "") print ENVIRON["RW_NOTE"]
        if (moving) { print "" > hist; print $0 > hist; print ph[cur]; print "" }
        next
      }
      moving { print > hist; next }
      { print }' "$f" > "$tmp" || { rm -f "$tmp"; exit 1; }
    cat "$tmp" > "$f"; rm -f "$tmp"
    put "$f" Status "$phase:in-progress"
    put "$f" Updated "$now"
    printf '%s\n' "${hist#$top/}"
    ;;
  list)
    for f in "$(tf_dir "$top")"/*/state.md; do
      [ -f "$f" ] || continue
      id=${f%/state.md}; id=${id##*/}
      printf '%s\t%s\t%s\n' "$id" "$(field "$f" Status)" "$(field "$f" Branch)"
    done
    ;;
  *) usage ;;
esac
