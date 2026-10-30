#!/usr/bin/env bash
# Status labels and assignee of a GitHub ticket (GT-<n>).
#
#   issue-label.sh setup                      create the tixforge labels that are missing
#   issue-label.sh <number> start [--force]   tixforge:in-progress, assign yourself
#   issue-label.sh <number> review            tixforge:in-review
#   issue-label.sh <number> merged            tixforge:merged (merged into the base, not released yet)
#   issue-label.sh <number> done              tixforge:done
#   issue-label.sh <number> canceled          tixforge:canceled
#   issue-label.sh <number> reset             tixforge:todo, unassign yourself (hand the ticket back)
#
# An issue carries exactly one status label: the others are removed.
# tixforge:out-of-sync is not a status and is left alone. start, review and
# reset refuse a closed issue; merged, done and canceled also apply to one
# (a release or a cancel closes it). Prints what was done in one line.
#
# Exit: 0 ok, 2 usage, 3 the issue is closed, 4 someone else is assigned
#       (start without --force), other: gh failed.
set -uo pipefail

usage() {
  grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
  exit 2
}

STATUS_LABELS="tixforge:todo tixforge:in-progress tixforge:in-review tixforge:merged tixforge:done tixforge:canceled"

# name<TAB>color<TAB>description of every label tixforge uses.
label_defs() {
  printf '%s\t%s\t%s\n' \
    tixforge:todo 0e8a16 "誰もまだ着手していない" \
    tixforge:in-progress 1d76db "dev を進めている（assignee が担当）" \
    tixforge:in-review fbca04 "PR のレビュー・マージ待ち" \
    tixforge:merged 5319e7 "Base にマージ済み・リリース待ち" \
    tixforge:done 6f42c1 "完了" \
    tixforge:canceled cfd3d7 "キャンセル済み" \
    tixforge:out-of-sync d93f0b "GitHub 上で本文かタイトルが直接編集された"
}

if [ "${1:-}" = setup ]; then
  [ $# -eq 1 ] || usage
  have=$(gh label list --limit 200 --json name --jq '.[].name') || exit $?
  made=""
  while IFS="$(printf '\t')" read -r name color desc; do
    printf '%s\n' "$have" | grep -qx "$name" && continue
    gh label create "$name" --color "$color" --description "$desc" > /dev/null || exit $?
    made="$made $name"
  done << EOF
$(label_defs)
EOF
  if [ -n "$made" ]; then echo "created labels:$made"; else echo "labels: all present"; fi
  exit 0
fi

[ $# -ge 2 ] && [ $# -le 3 ] || usage
n=$1 action=$2 force=${3:-}
[ -z "$force" ] || { [ "$force" = --force ] && [ "$action" = start ]; } || usage
case $action in
  start) want=tixforge:in-progress ;;
  review) want=tixforge:in-review ;;
  merged) want=tixforge:merged ;;
  done) want=tixforge:done ;;
  canceled) want=tixforge:canceled ;;
  reset) want=tixforge:todo ;;
  *) usage ;;
esac

info=$(gh issue view "$n" --json state,labels,assignees \
  --jq '.state, ([.labels[].name] | join(",")), ([.assignees[].login] | join(","))') || exit $?
state=$(printf '%s\n' "$info" | sed -n 1p)
labels=$(printf '%s\n' "$info" | sed -n 2p)
assignees=$(printf '%s\n' "$info" | sed -n 3p)

case $action in
  start | review | reset)
    [ "$state" = OPEN ] || {
      echo "issue #$n は閉じています（開き直さない）" >&2
      exit 3
    }
    ;;
esac

me=""
case $action in start | reset) me=$(gh api user --jq .login) || exit $? ;; esac

if [ "$action" = start ] && [ -z "$force" ]; then
  others=$(printf '%s' "$assignees" | tr ',' '\n' | grep -vx "$me" | paste -sd, -)
  if [ -n "$others" ]; then
    echo "issue #$n には他の人が assign されています: $others" >&2
    exit 4
  fi
fi

args=""
for l in $STATUS_LABELS; do
  [ "$l" = "$want" ] && continue
  case ",$labels," in *",$l,"*) args="$args --remove-label $l" ;; esac
done
args="$args --add-label $want"
note="#$n を $want に"
case $action in
  start)
    args="$args --add-assignee @me"
    note="${note}し、assignee に自分を追加"
    ;;
  reset) case ",$assignees," in *",$me,"*)
    args="$args --remove-assignee @me"
    note="${note}し、assignee から自分を外した"
    ;;
  esac ;;
esac

# shellcheck disable=SC2086 # $args is a list of flags without spaces in values
gh issue edit "$n" $args > /dev/null || exit $?
echo "$note"
