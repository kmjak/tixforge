#!/usr/bin/env bash
# GitHub tickets (GT-<n>) and their issues. The issue is the source of truth;
# .tixforge/<id>/ticket.md is a working copy that is not in git and is
# rebuilt from the issue. See references/github/.
#
#   issue-sync.sh create <draft-file>                     create the issue (tixforge:todo) and its working copy
#   issue-sync.sh check <number> [<ticket-file>]          sync verdict, how the issue was closed, details
#   issue-sync.sh pull <number> <ticket-file> [--accept-edited] [--dry-run]
#                                                         rebuild the working copy from the issue; prints the diff
#   issue-sync.sh push <number> <ticket-file> [--force] [--keep-original]
#                                                         write the working copy to the issue
#   issue-sync.sh adopt <number> <ticket-file>            working copy from an issue tixforge did not write
#   issue-sync.sh body <ticket-file>                      the issue body for a ticket (no GitHub access)
#
# check prints `<verdict>` on the first line, then key: value lines:
#   verdict     in-sync     the body's hash matches its title + ticket: only tixforge wrote it
#               edited      it does not: the title or the ticket was edited on GitHub
#               no-hash     markers but no hash; treated as in-sync
#               no-markers  the markers are gone (edited on GitHub, or not written by tixforge)
#   closed_as   open | completed | canceled | unexpected (closed some other way,
#               e.g. by hand); see closed_as() below
#   local       same | differs | missing: the ticket file (when given) against
#               the version tixforge last wrote to the issue. Only "same" means
#               the file may overwrite a direct edit on GitHub.
#   title, state, state_reason, labels, assignees (logins, comma-separated; last line)
#
# pull records the hash it saw in <dir>/.issue-hash; push refuses (exit 5)
# when the issue's hash has changed since, i.e. someone else pushed an edit
# after this copy was fetched. create prints number, url, id and file.
# push --keep-original first posts the current body as a comment (adopt).
#
# Exit: 0 ok, 2 usage, 3 no markers, 4 edited on GitHub, 5 changed since
#       fetched, 6 the ticket folder already exists (create), other: gh failed.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
. "$here/lib.sh"
hash_sh="$here/ticket-hash.sh"

usage() {
  grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
  exit 2
}

OUT_OF_SYNC=tixforge:out-of-sync

# --- ticket file ------------------------------------------------------------

ticket_title() { sed -n '1{s/^# *//; s/^[^:]*: *//; p;}' "$1"; }
ticket_body() { awk '/^## / { on = 1 } on' "$1"; } # first ## to the end

notice() { printf '%b\n' "$(msg issue_notice)"; }

# make_body <title> <ticket-body-file>
make_body() {
  local h
  h=$(bash "$hash_sh" hash "$1" < "$2")
  notice
  printf '\n<!-- tixforge:hash:%s -->\n<!-- tixforge:ticket:start -->\n' "$h"
  tr -d '\r' < "$2" | awk '{ a[NR] = $0 } END { n = NR; while (n > 0 && a[n] ~ /^[ \t]*$/) n--; for (i = 1; i <= n; i++) print a[i] }'
  printf '<!-- tixforge:ticket:end -->\n'
}

# --- issue ------------------------------------------------------------------

tmpd=$(mktemp -d) || exit 1
trap 'rm -rf "$tmpd"' EXIT

# load <number>: fills $tmpd/body and title, state, reason, labels, assignees.
load() {
  local info
  # One value per line: a tab-separated read would collapse empty fields.
  info=$(gh issue view "$1" --json title,state,stateReason,labels,assignees \
    --jq '.title, .state, (.stateReason // ""), ([.labels[].name] | join(",")), ([.assignees[].login] | join(","))') || exit $?
  gh issue view "$1" --json body --jq .body > "$tmpd/body" || exit $?
  title=$(printf '%s\n' "$info" | sed -n 1p)
  state=$(printf '%s\n' "$info" | sed -n 2p)
  reason=$(printf '%s\n' "$info" | sed -n 3p)
  labels=$(printf '%s\n' "$info" | sed -n 4p)
  assignees=$(printf '%s\n' "$info" | sed -n 5p)
}

# verdict: of the loaded issue.
verdict() {
  local stored
  bash "$hash_sh" extract < "$tmpd/body" > "$tmpd/ticket" || {
    echo no-markers
    return
  }
  stored=$(bash "$hash_sh" stored < "$tmpd/body") || {
    echo no-hash
    return
  }
  if [ "$(bash "$hash_sh" hash "$title" < "$tmpd/ticket")" = "$stored" ]; then echo in-sync; else echo edited; fi
}

stored_hash() { bash "$hash_sh" stored < "$tmpd/body" 2> /dev/null || true; }

has_label() { case ",$labels," in *",$1,"*) return 0 ;; *) return 1 ;; esac }

# closed_as <number>: how the loaded issue ended. Labels first (tixforge and
# its Actions set them), then what GitHub recorded: a merged PR or a commit
# with a closing keyword closed it (completed), or tixforge canceled it.
closed_as() {
  [ "$state" = CLOSED ] || {
    echo open
    return
  }
  if has_label tixforge:done || has_label tixforge:merged; then
    echo completed
    return
  fi
  if has_label tixforge:canceled; then
    echo canceled
    return
  fi
  local comments by_pr by_commit
  comments=$(gh issue view "$1" --json comments --jq '[.comments[].body | split("\n")[0]] | join("\n")' 2> /dev/null || true)
  if [ "$reason" = NOT_PLANNED ] && printf '%s\n' "$comments" | grep -q '^Canceled by tixforge: '; then
    echo canceled
    return
  fi
  if [ "$reason" = COMPLETED ]; then
    by_pr=$(gh issue view "$1" --json closedByPullRequestsReferences --jq '.closedByPullRequestsReferences | length' 2> /dev/null || echo 0)
    by_commit=$(gh api "repos/{owner}/{repo}/issues/$1/events" \
      --jq '[.[] | select(.event == "closed")] | last | .commit_id // ""' 2> /dev/null || true)
    if [ "${by_pr:-0}" != 0 ] || [ -n "$by_commit" ] || printf '%s\n' "$comments" | grep -q '^Closed by tixforge'; then
      echo completed
      return
    fi
  fi
  echo unexpected
}

hashfile() { printf '%s/.issue-hash\n' "$(dirname "$1")"; }

# write_copy <file> <id> <title> <ticket-body-file>
write_copy() {
  {
    printf '# %s: %s\n\n' "$2" "$3"
    cat "$4"
  } > "$1"
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case $cmd in
  body)
    [ $# -eq 1 ] || usage
    ticket_body "$1" > "$tmpd/ticket"
    make_body "$(ticket_title "$1")" "$tmpd/ticket"
    ;;

  create)
    [ $# -eq 1 ] || usage
    t=$(ticket_title "$1")
    ticket_body "$1" > "$tmpd/ticket"
    make_body "$t" "$tmpd/ticket" > "$tmpd/new"
    url=$(gh issue create --title "$t" --body-file "$tmpd/new" --label tixforge:todo) || exit $?
    url=$(printf '%s\n' "$url" | grep -Eo 'https://[^[:space:]]+/issues/[0-9]+' | tail -1)
    n=${url##*/}
    id="GT-$(printf '%06d' "$n")"
    file=$(ticket_file "$id")
    echo "number: $n"
    echo "url: $url"
    echo "id: $id"
    if [ -e "$(dirname "$file")" ]; then
      echo "the folder of $id already exists: $(dirname "$file")（手元のコピーは作っていない）" >&2
      exit 6
    fi
    ensure_workspace
    mkdir -p "$(dirname "$file")"
    write_copy "$file" "$id" "$t" "$tmpd/ticket"
    bash "$hash_sh" hash "$t" < "$tmpd/ticket" > "$(hashfile "$file")"
    echo "file: ${file#$(flow_top)/}"
    ;;

  check)
    [ $# -ge 1 ] && [ $# -le 2 ] || usage
    load "$1"
    verdict
    echo "closed_as: $(closed_as "$1")"
    if [ $# -eq 2 ]; then
      if [ -f "$2" ]; then
        ticket_body "$2" > "$tmpd/mine"
        if [ "$(bash "$hash_sh" hash "$(ticket_title "$2")" < "$tmpd/mine")" = "$(stored_hash)" ]; then
          echo "local: same"
        else
          echo "local: differs"
        fi
      else
        echo "local: missing"
      fi
    fi
    echo "title: $title"
    echo "state: $state"
    echo "state_reason: $reason"
    echo "labels: $labels"
    echo "assignees: $assignees"
    ;;

  pull)
    [ $# -ge 2 ] || usage
    n=$1 file=$2 accept="" dry=""
    shift 2
    for a in "$@"; do
      case $a in --accept-edited) accept=1 ;; --dry-run) dry=1 ;; *) usage ;; esac
    done
    load "$n"
    v=$(verdict)
    case $v in
      no-markers)
        echo "no-markers: issue #$n の本文に tixforge の目印がありません" >&2
        exit 3
        ;;
      edited) [ -n "$accept" ] || {
        echo "edited: issue #$n は GitHub 上で直接編集されています" >&2
        exit 4
      } ;;
    esac
    id="GT-$(printf '%06d' "$n")" # issue #42 is GT-000042
    write_copy "$tmpd/new" "$id" "$title" "$tmpd/ticket"
    if [ ! -f "$file" ]; then
      if [ -n "$dry" ]; then
        echo "would create: $file"
        cat "$tmpd/new"
        exit 0
      fi
      ensure_workspace
      mkdir -p "$(dirname "$file")"
      cat "$tmpd/new" > "$file"
      echo "created: $file"
    elif cmp -s "$file" "$tmpd/new"; then
      echo "unchanged: $file"
    else
      diff -u --label "$file (before)" --label "$file (issue #$n)" "$file" "$tmpd/new"
      [ -n "$dry" ] || cat "$tmpd/new" > "$file"
    fi
    [ -n "$dry" ] || stored_hash > "$(hashfile "$file")"
    ;;

  push)
    [ $# -ge 2 ] || usage
    n=$1 file=$2 force="" keep=""
    shift 2
    for a in "$@"; do
      case $a in --force) force=1 ;; --keep-original) keep=1 ;; *) usage ;; esac
    done
    load "$n"
    v=$(verdict)
    case $v in
      no-markers) [ -n "$force" ] || {
        echo "no-markers: issue #$n の本文に tixforge の目印がありません（--force で上書き）" >&2
        exit 3
      } ;;
      edited) [ -n "$force" ] || {
        echo "edited: issue #$n は GitHub 上で直接編集されています（--force で上書き）" >&2
        exit 4
      } ;;
    esac
    # Optimistic lock: the issue must still be the version this copy came from.
    if [ -z "$force" ] && [ -f "$(hashfile "$file")" ] && [ "$(cat "$(hashfile "$file")")" != "$(stored_hash)" ]; then
      echo "changed: issue #$n は、このコピーを取ってきた後に更新されています（他の人の edit の可能性）。取ってき直して差分を確かめてから編集し直してください" >&2
      exit 5
    fi
    t=$(ticket_title "$file")
    ticket_body "$file" > "$tmpd/local"
    make_body "$t" "$tmpd/local" > "$tmpd/new"
    if [ "$t" = "$title" ] && [ "$(tr -d '\r' < "$tmpd/body")" = "$(cat "$tmpd/new")" ]; then
      echo "unchanged: #$n"
    else
      if [ -n "$keep" ]; then
        {
          printf '%s\n\n' "$(msg original_body_comment)"
          cat "$tmpd/body"
        } > "$tmpd/original"
        gh issue comment "$n" --body-file "$tmpd/original" > /dev/null || exit $?
        echo "commented: the original body of #$n"
      fi
      gh issue edit "$n" --title "$t" --body-file "$tmpd/new" > /dev/null || exit $?
      echo "updated: #$n"
    fi
    bash "$hash_sh" hash "$t" < "$tmpd/local" > "$(hashfile "$file")"
    if has_label "$OUT_OF_SYNC"; then
      gh issue edit "$n" --remove-label "$OUT_OF_SYNC" > /dev/null && echo "removed label: $OUT_OF_SYNC"
    fi
    ;;

  adopt)
    # An issue written on GitHub (e.g. with the tixforge issue form): its
    # "### <section>" headings become the ticket's "## <section>" and an
    # unanswered field (_No response_) becomes "なし". GitHub is not touched;
    # push --force --keep-original writes it back after the user agrees.
    [ $# -eq 2 ] || usage
    n=$1 file=$2
    load "$n"
    [ "$(verdict)" = no-markers ] || {
      echo "issue #$n は tixforge の形式です（adopt ではなく pull を使う）" >&2
      exit 2
    }
    id="GT-$(printf '%06d' "$n")"
    tr -d '\r' < "$tmpd/body" | awk '
      /^###? / { sub(/^#+ /, "## "); on = 1 }
      on { if ($0 == "_No response_") $0 = "なし"; print }' > "$tmpd/ticket"
    if [ ! -s "$tmpd/ticket" ]; then
      {
        printf '## 背景\n'
        cat "$tmpd/body"
        printf '\n'
      } > "$tmpd/ticket"
    fi
    ensure_workspace
    mkdir -p "$(dirname "$file")"
    write_copy "$file" "$id" "$title" "$tmpd/ticket"
    echo "adopted: $file (#$n)"
    cat "$file"
    ;;

  *) usage ;;
esac
