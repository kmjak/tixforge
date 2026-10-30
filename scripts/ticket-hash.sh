#!/usr/bin/env bash
# The ticket part of a tixforge issue body, and its hash. Shared by
# issue-sync.sh and the tixforge-issue-guard GitHub Actions workflow (which
# gets a copy at .github/tixforge/ticket-hash.sh), so both compute the same
# hash. Keep it dependency-free: bash, sed, awk, sha256sum or shasum.
#
#   ticket-hash.sh extract < issue-body     the ticket between the markers
#   ticket-hash.sh stored < issue-body      the hash recorded in the body
#   ticket-hash.sh hash <title> < ticket    hash of title + ticket
#
# Body layout written by tixforge:
#   <notice>
#   <!-- tixforge:hash:<12 hex> -->
#   <!-- tixforge:ticket:start -->
#   <ticket from its first ## heading to the end>
#   <!-- tixforge:ticket:end -->
#
# Normalization before hashing: CR removed, trailing whitespace and blank
# lines at the end removed. Nothing else (inner spacing is content).
#
# Exit: 0 ok, 2 usage, 3 markers missing (extract) / no hash (stored).
set -uo pipefail

usage() {
  grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
  exit 2
}

START='<!-- tixforge:ticket:start -->'
END='<!-- tixforge:ticket:end -->'

normalize() {
  local s
  s=$(tr -d '\r')
  while :; do
    case $s in
      *[[:space:]]) s=${s%?} ;;
      *) break ;;
    esac
  done
  printf '%s' "$s"
}

sha() {
  if command -v sha256sum > /dev/null 2>&1; then sha256sum; else shasum -a 256; fi | cut -c1-12
}

case ${1:-} in
  extract)
    tr -d '\r' | awk -v s="$START" -v e="$END" '
      $0 == s { inside = 1; seen = 1; next }
      $0 == e && inside { inside = 0; closed = 1; next }
      inside { print }
      END { exit !(seen && closed) ? 3 : 0 }'
    ;;
  stored)
    h=$(tr -d '\r' | sed -n 's/^<!-- tixforge:hash:\([0-9a-f]*\) -->$/\1/p' | head -1)
    [ -n "$h" ] || exit 3
    printf '%s\n' "$h"
    ;;
  hash)
    [ $# -eq 2 ] || usage
    title=$(printf '%s' "$2" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    body=$(normalize)
    printf '%s\n%s' "$title" "$body" | sha
    ;;
  *) usage ;;
esac
