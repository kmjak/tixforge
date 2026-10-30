#!/usr/bin/env bash
# PreToolUse guard for tixforge, shipped in the tixforge plugin's hooks/hooks.json
# with the matcher Bash|Edit|Write|MultiEdit|NotebookEdit|mcp__.*. It runs
# for those tools in every project and acts only where a tixforge run is
# involved:
#
# On a run's branch (.tixforge/*/state.md whose Branch is the current branch):
#   deny  git push --force (any form), and gh pr create whose body does not
#         close the run's issue (Closes #N)
#   ask   every other push / PR creation, whatever the phase, so the user
#         confirms on the permission prompt even when git push is on the
#         allow list; the phase is shown in the prompt
#   ask   any git / gh subcommand outside the allow list below (merge,
#         rebase, reset, gh pr merge, gh api writes, ...), and GitHub / git
#         MCP tools that are not reads
# On the Base of an open run (the branch a run merges into):
#   the same, and a commit on the Base asks too (work goes on ticket branches)
# While a run is before Implement (research / approach / plan), editing a
#   file of the repository outside docs/ and .tixforge/ asks: nothing is
#   implemented before the Plan is approved. Not on the branch of a run that
#   is already implementing, where that run's own work goes on.
#
# Detection is deliberately loose (quotes stripped, bash -c / eval / env
# forms, git + push anywhere) because a false positive only costs a prompt.
# It is accident prevention, not a sandbox: any command Claude can run can
# be written so that it is not recognised.
#
# Output: nothing + exit 0 = no decision (normal permission flow).
# exit 2 = deny; stderr goes to Claude. JSON on stdout = ask; the reason
# goes to the user only.
set -uo pipefail
# shellcheck source=SCRIPTDIR/lib.sh
. "$(cd "$(dirname "$0")" && pwd)/lib.sh"

input=$(cat)
tool=$(printf '%s' "$input" | json_get tool_name)

# Cheap pre-filters: most calls never reach git.
case "$tool" in
  Bash | '') case "$input" in *git* | *gh*) ;; *) exit 0 ;; esac ;;
  Edit | Write | MultiEdit | NotebookEdit | mcp__*) ;;
  *) exit 0 ;;
esac
case "$tool" in mcp__*) case "$tool" in *[Gg][Ii][Tt]*) ;; *) exit 0 ;; esac ;; esac

deny() {
  {
    echo "[tixforge guard] $1"
    echo "この操作は tixforge のルールでブロックされました。コマンドを言い換えて回避せず、理由をユーザーに伝えて指示を待ってください。"
  } >&2
  exit 2
}

ask() {
  local reason
  reason=$(printf '[tixforge] %s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | tr '\n' ' ')
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"%s"}}\n' "$reason"
  exit 0
}

cwd=$PWD
c=$(printf '%s' "$input" | json_get cwd)
[ -n "$c" ] && cwd=$c

top=$(git -C "$cwd" rev-parse --show-toplevel 2> /dev/null) || exit 0

# --- Edit / Write before the Plan is approved ------------------------------

case "$tool" in
  Edit | Write | MultiEdit | NotebookEdit)
    early=""
    cur=$(git -C "$cwd" symbolic-ref --short -q HEAD 2> /dev/null || true)
    for f in "$(tf_dir "$top")"/*/state.md; do
      [ -f "$f" ] || continue
      s=$(field "$f" Status)
      case "$s" in
        research:* | approach:* | plan:*)
          id=${f%/state.md}
          id=${id##*/}
          early="${early}${early:+、}${id}（${s}）"
          ;;
        implement:* | review:* | pr:*)
          [ -n "$cur" ] && [ "$(field "$f" Branch)" = "$cur" ] && exit 0
          ;;
      esac
    done
    [ -n "$early" ] || exit 0
    path=$(printf '%s' "$input" | json_get tool_input.file_path)
    [ -n "$path" ] || path=$(printf '%s' "$input" | json_get tool_input.notebook_path)
    [ -n "$path" ] || ask "Plan の承認前の run があります：${early}。hook の入力から編集するファイルを読み取れなかったため、docs/・.tixforge/ の中かを判定できません。承認しますか？"
    case "$path" in /*) ;; *) path="$cwd/$path" ;; esac
    # Resolve symlinks (/tmp, /var on macOS) through the nearest existing
    # directory, as git does for the toplevel; the file may not exist yet.
    d=$path
    tail=""
    while [ ! -d "$d" ]; do
      tail="/${d##*/}$tail"
      d=${d%/*}
      [ -n "$d" ] || d=/
    done
    path="$(cd "$d" && pwd -P)$tail"
    case "$path" in
      "$top"/docs/* | "$top"/.tixforge/*) exit 0 ;;
      "$top"/*) ask "Plan の承認前の run があります：${early}。docs/・.tixforge/ 以外のファイル（${path#$top/}）を編集しようとしています。tixforge と無関係の作業なら許可してください。" ;;
      *) exit 0 ;;
    esac
    ;;
esac

# --- the run this branch belongs to ----------------------------------------

branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2> /dev/null) || exit 0

state=""
base_of=""
for f in "$(tf_dir "$top")"/*/state.md; do
  [ -f "$f" ] || continue
  if [ "$(field "$f" Branch)" = "$branch" ]; then
    state=$f
    break
  fi
  if [ -z "$base_of" ] && is_open_status "$(field "$f" Status)" && [ "$(field "$f" Base)" = "$branch" ]; then
    base_of=$f
  fi
done
[ -n "$state" ] || [ -n "$base_of" ] || exit 0

if [ -n "$state" ]; then
  status=$(field "$state" Status)
  base=$(field "$state" Base)
  where="ブランチ ${branch}、Status ${status}（${state#$top/}）"
else
  run=${base_of%/state.md}
  run=${run##*/}
  where="Base ブランチ ${branch}（進行中の run ${run} の Base）"
fi

# --- MCP -------------------------------------------------------------------

case "$tool" in
  mcp__*)
    verb=${tool##*__}
    case "$verb" in get* | list* | search* | read* | view* | fetch*) exit 0 ;; esac
    ask "MCP の ${tool} は git / GitHub への書き込みの可能性があります。${where}。許可しますか？"
    ;;
esac

# --- Bash ------------------------------------------------------------------

cmd=$(printf '%s' "$input" | json_get tool_input.command)
# The pre-filter saw git or gh in the input, so a command we cannot read is
# asked about, not passed.
[ -n "$cmd" ] || ask "hook の入力からコマンドを読み取れなかったため、push / PR 作成かを判定できません。${where}。承認しますか？"

# Precise forms: a command segment starts at line start or after ; & | ( {
# and may be prefixed by `command`, env assignments, or git/gh options.
seg_start='(^|[;&|({])[[:space:]]*(command[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
git_push_re="${seg_start}git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?)*[[:space:]]+push([[:space:]]|$)"
gh_pr_create_re="${seg_start}gh([[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?)*[[:space:]]+pr[[:space:]]+create([[:space:]]|$)"

# Loose forms: words anywhere once quotes and backslashes are removed, so
# bash -c "git push", eval, env, "git" push and gh api .../pulls are caught.
# `stash push` is local and dropped first.
unquoted=$(printf '%s\n' "$cmd" | tr -d "\"'\\\\")
norm=$(printf '%s\n' "$unquoted" | sed -E 's/stash[[:space:]]+push//g')
has_word() { printf '%s\n' "$norm" | grep -Eq "(^|[^[:alnum:]_-])$1([^[:alnum:]_-]|$)"; }

is_pr_create=0
precise_pr=0
printf '%s\n' "$cmd" | grep -Eq "$gh_pr_create_re" && {
  is_pr_create=1
  precise_pr=1
}
if has_word gh && { { has_word pr && has_word create; } || { has_word api && has_word pulls; }; }; then
  is_pr_create=1
fi
is_push=0
precise_push=0
printf '%s\n' "$cmd" | grep -Eq "$git_push_re" && {
  is_push=1
  precise_push=1
}
has_word git && has_word push && is_push=1

# Allow list: every git / gh in command position must be a read or a local,
# recoverable step. The first one that is not becomes $other.
other=""
has_arg() { # has_arg <pattern>...: one of the remaining words matches
  local w p
  for w in $rest; do for p in "$@"; do
    # shellcheck disable=SC2254 # $p is a pattern on purpose
    case "$w" in $p) return 0 ;; esac
  done done
  return 1
}
git_ok() { # git_ok <sub>
  case "$1" in
    '' | push | status | diff | log | show | rev-parse | symbolic-ref | ls-files | ls-tree | ls-remote | check-ignore | merge-base | merge-tree | add | rm | mv | blame | grep | describe | cat-file | for-each-ref | rev-list | shortlog | name-rev | show-ref | diff-tree | diff-files | diff-index | help | version | --version) return 0 ;;
    commit)
      [ -z "$state" ] && return 1
      has_arg --amend && return 1
      return 0
      ;;
    # Switching and fetching are safe unless forced: -f / --discard-changes
    # throw away local changes, -C / -B reset an existing branch, and a
    # +refspec or --force overwrites a local branch.
    switch) ! has_arg -f --force --discard-changes -C '--force-create' '--force-create=*' ;;
    checkout) [ -z "$rest" ] || { has_arg -b && ! has_arg -B -f --force; } ;;
    fetch) ! has_arg '+*' '*:+*' -f --force ;;
    branch) ! has_arg '-[dDmMcCfu]' '--delete' '--move' '--copy' '--force' '--set-upstream-to*' '--unset-upstream' '--edit-description' ;;
    stash) [ -z "$rest" ] || has_arg push list show pop apply save ;;
    tag) [ -z "$rest" ] || has_arg -l '--list' ;;
    config) has_arg --get '--get-all' '--get-regexp' --list -l ;;
    remote) [ -z "$rest" ] || has_arg -v get-url show ;;
    worktree) has_arg list ;;
    *) return 1 ;;
  esac
}
gh_ok() { # gh_ok <sub> <sub2>
  case "$1 $2" in
    'pr create'*) return 0 ;; # handled above: Closes check and a prompt
    'pr view'* | 'pr list'* | 'pr checks'* | 'pr diff'* | 'pr status'*) return 0 ;;
    'issue view'* | 'issue list'* | 'issue status'*) return 0 ;;
    'run view'* | 'run list'* | 'run watch'* | 'repo view'* | 'auth status'* | 'label list'*) return 0 ;;
    'release view'* | 'release list'* | 'workflow view'* | 'workflow list'* | 'search '*) return 0 ;;
    'status '* | 'help '* | 'version '* | '--version '* | ' ') return 0 ;;
    'api '*) ! has_arg -X '--method' -f -F '--field' '--raw-field' '--input' '-X*' '--method=*' ;;
    *) return 1 ;;
  esac
}

segments=$(printf '%s\n' "$unquoted" | tr ';&|(){}`' '\n\n\n\n\n\n\n\n')
set -f
while IFS= read -r seg; do
  [ -n "$other" ] && break
  # shellcheck disable=SC2206 # word splitting (globbing off) is the point
  words=($seg)
  n=${#words[@]}
  i=0
  cmdpos=1
  while [ $i -lt $n ] && [ $cmdpos -eq 1 ]; do
    w=${words[$i]}
    case "$w" in
      [A-Za-z_]*=* | command | env | sudo | exec | xargs | eval | time | nohup | nice | bash | sh | zsh | -*)
        i=$((i + 1))
        continue
        ;;
      git | */git)
        j=$((i + 1))
        while [ $j -lt $n ]; do
          case "${words[$j]}" in
            -C | -c | --git-dir | --work-tree | --namespace) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        sub=${words[$j]:-}
        rest="${words[*]:$((j + 1))}"
        git_ok "$sub" || other="git ${sub}"
        ;;
      gh | */gh)
        j=$((i + 1))
        while [ $j -lt $n ]; do
          case "${words[$j]}" in
            -R | --repo | --hostname) j=$((j + 2)) ;;
            -*) j=$((j + 1)) ;;
            *) break ;;
          esac
        done
        sub=${words[$j]:-}
        sub2=${words[$((j + 1))]:-}
        rest="${words[*]:$((j + 1))}"
        gh_ok "$sub" "$sub2" || other="gh ${sub} ${sub2}"
        ;;
    esac
    cmdpos=0
  done
done << EOF
$segments
EOF
set +f

[ $is_push -eq 1 ] || [ $is_pr_create -eq 1 ] || [ -n "$other" ] || exit 0

# deny: force push, in any form, inside a segment that is a git push (quotes
# removed; bash -c / eval / env / sudo wrappers allowed). A force flag seen
# only by the loose match (e.g. "push -f" inside a commit message) asks.
force_note=""
if [ $is_push -eq 1 ]; then
  force_re='(^|[[:space:]])(--force|--force-with-lease(=[^[:space:]]*)?|--force-if-includes|-[A-Za-z]*f[A-Za-z]*)([[:space:]]|$)|[[:space:]]\+[^[:space:]]'
  wrap='((command|env|sudo|exec|eval|nohup|time|(ba|z)?sh[[:space:]]+-c)[[:space:]]+|[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
  push_seg_re="^[[:space:]]*${wrap}git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+--?[A-Za-z][A-Za-z-]*(=[^[:space:]]+)?)*[[:space:]]+push([[:space:]]|$)"
  push_segs=$(printf '%s\n' "$unquoted" | tr ';&|(){}`' '\n\n\n\n\n\n\n\n' | grep -E "$push_seg_re" || true)
  if [ -n "$push_segs" ] && printf '%s\n' "$push_segs" | sed -E 's/.*[[:space:]]push([[:space:]]|$)/ /' | grep -Eq "$force_re"; then
    deny "force push は禁止です（ブランチ ${branch}）。履歴の書き換えが本当に必要なら、ユーザー自身が ! git push --force-with-lease などで実行してください。"
  fi
  printf '%s\n' "$norm" | grep -Eo 'push([[:space:]][^;&|]*)?' | grep -Eq "$force_re" \
    && force_note="（force push の可能性あり。コマンドを確認してください）"
fi

if [ -z "$state" ]; then
  # On the Base of an open run.
  if [ $is_push -eq 1 ]; then what="push"; elif [ $is_pr_create -eq 1 ]; then what="PR 作成"; else what=$other; fi
  ask "⚠ ${where} で ${what} を実行しようとしています。tixforge の作業はチケットのブランチで行います。承認しますか？${force_note}"
fi

# deny: the PR must close the run's issue. Only the precise form has a body
# we can read; anything else is left to the prompt.
run_id=${state%/state.md}
run_id=${run_id##*/}
issue=$(issue_of "$run_id")
if [ $precise_pr -eq 1 ] && [ -n "$issue" ]; then
  haystack=$cmd
  body_file=$(printf '%s\n' "$cmd" | grep -Eo '(--body-file|-F)([[:space:]]+|=)[^[:space:];&|]+' | head -1 \
    | sed -E 's/^(--body-file|-F)([[:space:]]+|=)//; s/^["'\'']//; s/["'\'']$//')
  if [ -n "$body_file" ]; then
    case "$body_file" in /*) ;; *) body_file="$cwd/$body_file" ;; esac
    [ -f "$body_file" ] && haystack="$haystack
$(cat "$body_file")"
  fi
  if ! printf '%s\n' "$haystack" | grep -Eiq "(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]+#${issue}([^0-9]|$)"; then
    deny "PR 本文に \"Closes #${issue}\" がありません。issue #${issue} を閉じる紐付けを本文に入れてから作成してください（--fill や本文なしでは作成できません）。"
  fi
fi

if [ $is_push -eq 0 ] && [ $is_pr_create -eq 0 ]; then
  ask "${other} は tixforge の許可リストにない git / gh 操作です（merge・rebase・reset・gh pr merge など）。${where}。承認しますか？"
fi

# ask: everything else that leaves the machine. The phase goes in the prompt.
if [ $is_pr_create -eq 1 ]; then
  what="PR 作成"
  obj="PR 作成を"
else
  what="push"
  obj="push を"
fi
detail="${where}、Base ${base:-—}"
[ $is_pr_create -eq 1 ] && [ -n "$issue" ] && detail="${detail}、Closes #${issue}"
[ -n "$other" ] && detail="${detail}、ほかに ${other} を含む"
pr_url=$(awk '/^## PR/{p=1; next} /^## /{p=0} p' "$state" | grep -Eo -m1 'https://[^[:space:]]+/pull/[0-9]+' || true)

case "$status" in
  pr:awaiting-approval)
    note="PR ゲート：${obj}承認しますか？"
    ;;
  pr:awaiting-review | pr:in-progress | pr:ready-to-merge)
    if [ $is_pr_create -eq 1 ] && [ -n "$pr_url" ]; then
      note="⚠ PR は既にあります（${pr_url}）。${obj}承認しますか？"
    elif [ -n "$pr_url" ]; then
      note="PR 作成後の ${what}（${pr_url}）を承認しますか？"
    else
      note="⚠ ## PR に URL がありません。${obj}承認しますか？"
    fi
    ;;
  done | canceled)
    note="⚠ このブランチの run は ${status} です（完了済み）。${obj}承認しますか？"
    ;;
  *)
    note="⚠ まだ PR ゲート前です。${obj}承認しますか？"
    ;;
esac
note="${note}${force_note}"
if { [ $is_push -eq 1 ] && [ $precise_push -eq 0 ]; } || { [ $is_pr_create -eq 1 ] && [ $precise_pr -eq 0 ]; }; then
  note="${note}（コマンドの形から ${what} の可能性があると判断）"
fi
ask "${note} ${detail}"
