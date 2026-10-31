#!/usr/bin/env bash
# Ticket ids for tixforge. Numbers are handled as strings, so a zero-padded
# id is never read as octal.
#
#   ticket-id.sh normalize <GT-000123 | #123 | 123>   canonical id
#   ticket-id.sh number <GT-id>                        issue number (123)
#   ticket-id.sh detect <text…>                        the id in an argument
#   ticket-id.sh exists <id>                           what the number is on GitHub
#
# Ids: GT-<6 digits> is GitHub issue #N. normalize accepts the prefix in any
# case but only with exactly 6 digits (7 or more when the number needs
# them); a wrong digit count is an error, not padded, so a mistyped id does
# not silently point at another ticket. #123 and a bare 123 are issue #123.
# LT- (v2's local tickets) is an error that points at the migration.
#
# detect prints two lines: `id: <id>` (or `id: none`, or `invalid: <token>`)
# and `rest: <the text without the id>`. An id is taken from GT-/#N (and
# LT-, to report it) anywhere in the text, and from a bare number only when
# the whole text is that number ("404 ページを作る" has no id).
#
# exists prints one of: issue, pull-request (the number is a PR, not an
# issue), none.
#
# Exit: 0 ok, 1 exists: none, 2 invalid id or usage, 3 gh failed.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

usage() {
  grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
  exit 2
}

# fmt <kind> <digits>: kind-000123 (never truncated).
fmt() {
  local n
  n=$(printf '%s' "$2" | sed 's/^0*//')
  [ -n "$n" ] || {
    echo "ticket number is zero" >&2
    return 2
  }
  while [ ${#n} -lt $ID_PAD ]; do n="0$n"; done
  printf '%s-%s\n' "$1" "$n"
}

# norm <token>: canonical id, or an error (exit 2) that shows the right form.
norm() {
  local t up d
  t=$1
  up=$(printf '%s' "$t" | tr '[:lower:]' '[:upper:]')
  case $up in
    \#*)
      d=${up#\#}
      case $d in '' | *[!0-9]*) ;; *)
        fmt GT "$d"
        return
        ;;
      esac
      ;;
    LT-*)
      echo "LT- のチケットは使えない: ${t}（v3 はチケットを GitHub issue に置く。/tixforge:project update で issue に移す）" >&2
      return 2
      ;;
    GT-*)
      d=${up#GT-}
      case $d in
        '' | *[!0-9]*) ;;
        *)
          [ -n "$(issue_of "GT-$d")" ] || {
            echo "invalid ticket id: ${t}（番号 0 は使えない）" >&2
            return 2
          }
          if is_ticket_id "$up"; then
            printf '%s\n' "$up"
            return 0
          fi
          echo "invalid ticket id: ${t}（GT-000123 のように 6 桁で書く。桁は自動で補わない。id を推測で直さず、正しい id をユーザーに確認すること）" >&2
          return 2
          ;;
      esac
      ;;
    *[!0-9]* | '') ;;
    *)
      fmt GT "$up"
      return
      ;;
  esac
  echo "invalid ticket id: ${t}（GT-000123・#123・123 のどれかで書く。id を推測で直さず、正しい id をユーザーに確認すること）" >&2
  return 2
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  normalize)
    [ $# -eq 1 ] || usage
    norm "$1"
    ;;
  number)
    [ $# -eq 1 ] || usage
    id=$(norm "$1") || exit 2
    issue_of "$id"
    ;;
  detect)
    [ $# -ge 1 ] || usage
    text="$*"
    trimmed=$(printf '%s' "$text" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    token=""
    case $trimmed in
      '' | *[!0-9]*) token=$(printf '%s\n' "$text" | grep -Eo '(^|[^A-Za-z0-9#])([LlGg][Tt]-[0-9]+|#[0-9]+)' | head -1 | sed -E 's/^[^A-Za-z#]//') ;;
      *) token=$trimmed ;;
    esac
    if [ -z "$token" ]; then
      echo "id: none"
      printf 'rest: %s\n' "$trimmed"
      exit 0
    fi
    rest=$(printf '%s' "$text" | awk -v t="$token" '{ i = index($0, t); if (i) $0 = substr($0, 1, i - 1) substr($0, i + length(t)); print }' \
      | sed 's/[[:space:]][[:space:]]*/ /g; s/^ //; s/ $//')
    if id=$(norm "$token" 2> /dev/null); then
      printf 'id: %s\n' "$id"
    else
      printf 'invalid: %s\n' "$token"
    fi
    printf 'rest: %s\n' "$rest"
    ;;
  exists)
    [ $# -eq 1 ] || usage
    id=$(norm "$1") || exit 2
    n=$(issue_of "$id")
    # The issues API answers for pull requests too, with a pull_request key.
    out=$(gh api "repos/{owner}/{repo}/issues/$n" --jq 'if .pull_request then "pull-request" else "issue" end' 2>&1)
    case $out in
      issue | pull-request) echo "$out" ;;
      *"Not Found"* | *404*)
        echo none
        exit 1
        ;;
      *)
        echo "$out" >&2
        exit 3
        ;;
    esac
    ;;
  *) usage ;;
esac
