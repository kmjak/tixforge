#!/usr/bin/env bash
# Tests for scripts/guard.sh.
#
# Feeds the guard the same JSON Claude Code sends to a PreToolUse(Bash) hook
# and checks its decision:
#   pass   exit 0, no output (normal permission flow)
#   ask    exit 0, permissionDecision "ask"
#   deny   exit 2, or permissionDecision "deny"
#
# Usage: bash tests/guard.test.sh   (also run it with /bin/bash on macOS for 3.2)
set -u

here=$(cd "$(dirname "$0")" && pwd)
guard="$here/../scripts/guard.sh"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Isolate from the user's git config (signing, hooks, default branch).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

# A PATH without jq: symlinks to only the tools the guard and git need.
nojq="$tmp/nojq-bin"
mkdir -p "$nojq"
for t in bash git awk grep sed tr head cat dirname; do
  p=$(command -v "$t") && ln -s "$p" "$nojq/$t"
done

# --- fixtures ---------------------------------------------------------------

# A repo whose branch GT-000001-login is owned by a tixforge run.
tfrepo="$tmp/tf-repo"
git init -q -b main "$tfrepo"
git -C "$tfrepo" commit -q --allow-empty -m init
git -C "$tfrepo" checkout -q -b GT-000001-login
mkdir -p "$tfrepo/.tixforge/GT-000001"
printf '*\n!.gitignore\n!config.yml\n' > "$tfrepo/.tixforge/.gitignore"
printf '# GT-000001: Login\n\n## 背景\n' > "$tfrepo/.tixforge/GT-000001/ticket.md"

# set_state <status> [pr-url]
set_state() {
  cat > "$tfrepo/.tixforge/GT-000001/state.md" << EOF
# Run: GT-000001

| Field   | Value                        |
|---------|------------------------------|
| Status  | $1                           |
| Branch  | GT-000001-login                |
| Base    | main                         |
| Updated | 2026-01-01 00:00             |

## Implementation Log

## PR
${2:-}
EOF
}

# A repo with no tixforge at all.
plain="$tmp/plain-repo"
git init -q -b main "$plain"
git -C "$plain" commit -q --allow-empty -m init

# --- runner -----------------------------------------------------------------

# json_str <s>: s as a JSON string literal (enough for these fixtures).
json_str() {
  printf '"%s"' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')"
}

# verdict_of <dir> <json> [PATH]: prints pass | ask | deny
verdict_of() {
  local dir=$1 path=${3:-} out code
  [ -n "$path" ] || path=$PATH
  out=$(cd "$dir" && printf '%s' "$2" | PATH=$path bash "$guard" 2> /dev/null)
  code=$?
  if [ $code -eq 2 ]; then
    echo deny
    return
  fi
  case "$out" in
    *'"permissionDecision"'*'"deny"'*) echo deny ;;
    *'"permissionDecision"'*'"ask"'*) echo ask ;;
    '') [ $code -eq 0 ] && echo pass || echo "error($code)" ;;
    *) echo "unexpected($code): $out" ;;
  esac
}

# decide <dir> <command> [PATH]: a Bash call
decide() {
  verdict_of "$1" "$(printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s}' \
    "$(json_str "$2")" "$(json_str "$1")")" "${3:-}"
}

# expect_tool <want> <dir> <tool> <tool_input-json>: any other tool
expect_tool() {
  local got
  got=$(verdict_of "$2" "$(printf '{"tool_name":"%s","tool_input":%s,"cwd":%s}' "$3" "$4" "$(json_str "$2")")")
  if [ "$got" = "$1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  [%s] %s %s\n      want %s, got %s\n' "$state" "$3" "$4" "$1" "$got"
  fi
}

pass=0
fail=0
# expect <want> <dir> <command> [PATH]
expect() {
  local want=$1 got
  got=$(decide "$2" "$3" "${4:-}")
  if [ "$got" = "$want" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  [%s] %s\n      want %s, got %s\n' "$state" "$3" "$want" "$got"
  fi
}

# reason_has <dir> <command> <text> [PATH]: the ask prompt mentions text
reason_has() {
  local out
  out=$(cd "$1" && printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s}' \
    "$(json_str "$2")" "$(json_str "$1")" \
    | PATH=${4:-$PATH} bash "$guard" 2> /dev/null)
  case "$out" in
    *"$3"*) pass=$((pass + 1)) ;;
    *)
      fail=$((fail + 1))
      printf 'FAIL  [%s] %s\n      reason lacks "%s": %s\n' "$state" "$2" "$3" "$out"
      ;;
  esac
}

# --- cases ------------------------------------------------------------------

state="no tixforge"
expect pass "$plain" 'git push'
expect pass "$plain" 'gh pr create --fill'
expect pass "$tmp" 'git push' # not a git repo

state="tixforge repo, unrelated branch"
git -C "$tfrepo" checkout -q -b other
set_state implement:in-progress
expect pass "$tfrepo" 'git push'
expect pass "$tfrepo" 'git merge main'
expect pass "$tfrepo" 'git commit -m x'
git -C "$tfrepo" checkout -q GT-000001-login

state="implement:in-progress"
set_state implement:in-progress
expect pass "$tfrepo" 'git status'
expect pass "$tfrepo" 'git stash push -m wip'
expect pass "$tfrepo" 'echo pushed'
expect ask "$tfrepo" 'git push'
expect ask "$tfrepo" 'git push -u origin GT-000001-login'
expect ask "$tfrepo" 'git -C . push'
expect ask "$tfrepo" 'command git push'
expect ask "$tfrepo" 'FOO=1 git push'
expect ask "$tfrepo" 'cd . && git push'
expect ask "$tfrepo" 'gh pr create --title t --body "Closes #1"'
expect deny "$tfrepo" 'gh pr create --fill'
expect deny "$tfrepo" 'git push --force'
reason_has "$tfrepo" 'git push' 'PR ゲート前'
reason_has "$tfrepo" 'git push' 'implement:in-progress'

state="pr:awaiting-approval"
set_state pr:awaiting-approval
expect ask "$tfrepo" 'git push -u origin GT-000001-login'
expect deny "$tfrepo" 'git push --force'
expect deny "$tfrepo" 'git push -f'
expect deny "$tfrepo" 'git push --force-with-lease'
expect deny "$tfrepo" 'git push origin +GT-000001-login'
expect ask "$tfrepo" 'gh pr create --title t --body "Closes #1"'
expect ask "$tfrepo" 'gh pr create --title t --body "fixes #1"'
expect deny "$tfrepo" 'gh pr create --title t --body "Closes #12"'
expect deny "$tfrepo" 'gh pr create --fill'
printf 'Summary\n\nCloses #1\n' > "$tmp/body.md"
expect ask "$tfrepo" "gh pr create --title t --body-file $tmp/body.md"
printf 'Summary\n' > "$tmp/body-noclose.md"
expect deny "$tfrepo" "gh pr create --title t --body-file $tmp/body-noclose.md"
reason_has "$tfrepo" 'git push' 'PR ゲート'
reason_has "$tfrepo" 'git push' 'Base main'
reason_has "$tfrepo" 'gh pr create --title t --body "Closes #1"' 'Closes #1'

state="pr:awaiting-review"
set_state pr:awaiting-review 'https://github.com/o/r/pull/9'
expect ask "$tfrepo" 'git push'
expect ask "$tfrepo" 'gh pr create --title t --body "Closes #1"'
reason_has "$tfrepo" 'gh pr create --title t --body "Closes #1"' 'PR は既にあります'

state="pr:in-progress"
set_state pr:in-progress
expect ask "$tfrepo" 'git push'
reason_has "$tfrepo" 'git push' 'URL がありません'
set_state pr:in-progress 'https://github.com/o/r/pull/9'
expect ask "$tfrepo" 'git push'
reason_has "$tfrepo" 'git push' 'pull/9'

# Rewordings the precise patterns miss; the loose match asks.
state="implement:in-progress (rewordings)"
set_state implement:in-progress
expect ask "$tfrepo" 'bash -c "git push"'
expect ask "$tfrepo" 'eval "git push"'
expect ask "$tfrepo" 'env git push'
expect ask "$tfrepo" '"git" push'
expect ask "$tfrepo" "sh -c 'git push origin HEAD'"
expect ask "$tfrepo" 'gh api repos/o/r/pulls -f title=t -f head=GT-000001-login -f base=main'
expect ask "$tfrepo" 'gh pr "create" --fill'
expect deny "$tfrepo" 'bash -c "git push --force"'
expect ask "$tfrepo" 'echo "run git push later"' # accepted false positive
reason_has "$tfrepo" 'bash -c "git push"' '可能性'

# Allow list: git / gh beyond push and PR creation.
state="implement:in-progress (allow list)"
set_state implement:in-progress
expect pass "$tfrepo" 'git log --oneline main..HEAD'
expect pass "$tfrepo" 'git diff main...HEAD'
expect pass "$tfrepo" 'git merge-tree --write-tree main GT-000001-login' # read-only conflict check (pr.md)
expect pass "$tfrepo" 'git add -A && git commit -m "feat: x"'
expect pass "$tfrepo" 'git switch main'
expect pass "$tfrepo" 'git checkout -b GT-000001-login-2'
expect pass "$tfrepo" 'git branch'
expect pass "$tfrepo" 'git stash list'
expect pass "$tfrepo" 'git -C . status'
expect pass "$tfrepo" 'grep -rn git src'
expect pass "$tfrepo" 'gh pr view 9 --json state'
expect pass "$tfrepo" 'gh pr checks 9'
expect pass "$tfrepo" 'gh issue view 1 --json body --jq .body'
expect pass "$tfrepo" 'gh api repos/o/r/issues/1'
expect ask "$tfrepo" 'git merge main'
expect ask "$tfrepo" 'git rebase main'
expect ask "$tfrepo" 'git reset --hard HEAD~1'
expect ask "$tfrepo" 'git commit --amend --no-edit'
expect ask "$tfrepo" 'git checkout -- src/a.ts'
expect ask "$tfrepo" 'git branch -D GT-000001-login'
expect ask "$tfrepo" 'git stash drop'
expect ask "$tfrepo" 'git clean -fd'
expect ask "$tfrepo" 'gh pr merge 9 --squash'
expect ask "$tfrepo" 'gh issue close 1'
expect ask "$tfrepo" 'gh api -X PUT repos/o/r/pulls/9/merge'
expect ask "$tfrepo" 'bash -c "git merge main"'
expect ask "$tfrepo" 'cd . && git reset --hard'
reason_has "$tfrepo" 'gh pr merge 9' 'gh pr merge'
# Forced forms of switch / checkout / fetch lose work or move a branch.
expect pass "$tfrepo" 'git switch -c GT-000001-login-3'
expect pass "$tfrepo" 'git fetch origin'
expect pass "$tfrepo" 'git fetch origin main:main'
expect ask "$tfrepo" 'git switch -f main'
expect ask "$tfrepo" 'git switch --discard-changes main'
expect ask "$tfrepo" 'git switch -C GT-000001-login HEAD~1'
expect ask "$tfrepo" 'git switch --force-create GT-000001-login HEAD~1'
expect ask "$tfrepo" 'git checkout -B GT-000001-login HEAD~1'
expect ask "$tfrepo" 'git checkout -f -b x'
expect ask "$tfrepo" 'git fetch origin +main:main'
expect ask "$tfrepo" 'git fetch -f origin main:main'

# "push -f" in a commit message is not a force push: it asks, it is not denied.
state="force push wording"
expect ask "$tfrepo" "git commit -m 'docs: explain why push -f is banned'"
reason_has "$tfrepo" "git commit -m 'docs: explain why push -f is banned'" 'force push の可能性'
expect deny "$tfrepo" 'git add -A && git push -f origin GT-000001-login'
expect deny "$tfrepo" 'eval "git push --force-with-lease"'

# The Base of an open run.
state="Base of an open run"
git -C "$tfrepo" checkout -q main
expect pass "$tfrepo" 'git status'
expect pass "$tfrepo" 'git log'
expect pass "$tfrepo" 'git switch GT-000001-login'
expect ask "$tfrepo" 'git merge --no-ff GT-000001-login'
expect ask "$tfrepo" 'git commit -m x'
expect ask "$tfrepo" 'git push'
expect deny "$tfrepo" 'git push --force'
reason_has "$tfrepo" 'git commit -m x' 'Base ブランチ main'
set_state done
expect pass "$tfrepo" 'git merge --no-ff GT-000001-login' # the run is closed
set_state implement:in-progress
git -C "$tfrepo" checkout -q GT-000001-login

# A push on the branch of a finished run says so instead of "before the PR gate".
state="finished run"
set_state done
expect ask "$tfrepo" 'git push origin GT-000001-login'
reason_has "$tfrepo" 'git push origin GT-000001-login' '完了済み'
set_state canceled
reason_has "$tfrepo" 'git push origin GT-000001-login' 'canceled'
set_state implement:in-progress

# MCP tools: GitHub / git writes ask where a run is involved.
state="MCP"
expect_tool ask "$tfrepo" mcp__github__merge_pull_request '{"pullNumber":9}'
expect_tool pass "$tfrepo" mcp__github__get_pull_request '{"pullNumber":9}'
expect_tool pass "$tfrepo" mcp__slack__post_message '{}'
expect_tool pass "$plain" mcp__github__merge_pull_request '{"pullNumber":9}'

# Edit / Write before the Plan is approved.
state="Edit before Plan approval"
set_state plan:awaiting-approval
expect_tool ask "$tfrepo" Edit "{\"file_path\":\"$tfrepo/src/a.ts\"}"
expect_tool ask "$tfrepo" Write "{\"file_path\":\"$tfrepo/new/dir/b.ts\"}"
expect_tool pass "$tfrepo" Edit "{\"file_path\":\"$tfrepo/docs/context/overview.md\"}"
expect_tool pass "$tfrepo" Write "{\"file_path\":\"$tfrepo/.tixforge/GT-000001/state.md\"}"
expect_tool pass "$tfrepo" Write "{\"file_path\":\"$tmp/elsewhere.txt\"}"
set_state implement:in-progress
expect_tool pass "$tfrepo" Edit "{\"file_path\":\"$tfrepo/src/a.ts\"}"
# Another run still before Implement: work on an implementing run's branch
# goes on; anywhere else, editing asks.
mkdir -p "$tfrepo/.tixforge/GT-000002"
printf '| Field   | Value |\n|---|---|\n| Status  | approach:in-progress |\n| Branch  | — |\n' > "$tfrepo/.tixforge/GT-000002/state.md"
expect_tool pass "$tfrepo" Edit "{\"file_path\":\"$tfrepo/src/a.ts\"}"
git -C "$tfrepo" checkout -q main
expect_tool ask "$tfrepo" Edit "{\"file_path\":\"$tfrepo/src/a.ts\"}"
git -C "$tfrepo" checkout -q GT-000001-login
rm -rf "$tfrepo/.tixforge/GT-000002"
set_state implement:in-progress

# A branch with no issue (a local ticket v2 left behind) needs no Closes line.
state="v2 local ticket"
mkdir -p "$tfrepo/.tixforge/LT-000003"
printf '| Field   | Value |\n|---|---|\n| Status  | pr:awaiting-approval |\n| Branch  | LT-000003-x |\n| Base    | main |\n' > "$tfrepo/.tixforge/LT-000003/state.md"
git -C "$tfrepo" checkout -q -b LT-000003-x
expect ask "$tfrepo" 'gh pr create --title t --body "no issue"'
git -C "$tfrepo" checkout -q GT-000001-login
git -C "$tfrepo" branch -q -D LT-000003-x
rm -rf "$tfrepo/.tixforge/LT-000003"

# The guard reads the hook input without jq: the same decisions without it.
state="no jq"
set_state implement:in-progress
expect ask "$tfrepo" 'git push' "$nojq"
expect pass "$tfrepo" 'git status' "$nojq"
expect ask "$tfrepo" 'git reset --hard' "$nojq"
expect pass "$plain" 'git stash push -m wip' "$nojq"
expect pass "$plain" 'git push' "$nojq"
git -C "$tfrepo" checkout -q main
expect ask "$tfrepo" 'git push' "$nojq"
git -C "$tfrepo" checkout -q GT-000001-login
reason_has "$tfrepo" 'git push' 'PR ゲート前' "$nojq"

# JSON the fixtures' json_str does not write: escapes, and "command" inside
# another string or object.
state="hook input"
expect_tool pass "$tfrepo" Bash '{"command":"git st\u0061tus"}'
expect_tool ask "$tfrepo" Bash '{"command":"echo \"a\\\\\"\ngit push"}'
expect_tool ask "$tfrepo" Bash '{"description":"\"command\":\"git status\"","command":"git push"}'
expect_tool pass "$tfrepo" Bash '{"x":{"command":"git push"},"command":"git status"}'
expect_tool pass "$tfrepo" Bash '{"description":"git push","command":"ls"}'
# A command that is not a string cannot be read: ask on a run's branch.
expect_tool ask "$tfrepo" Bash '{"command":["git push"]}'
expect_tool pass "$plain" Bash '{"command":["git push"]}'

# The JSON Claude Code sends, run from another directory (the guard must go
# by the input's cwd, not its own) and without jq on PATH.
hook_json() { # hook_json <cwd-json-string> <tool> <tool_input-json>
  printf '{"session_id":"s1","transcript_path":"/tmp/t.jsonl","cwd":%s,"permission_mode":"default","hook_event_name":"PreToolUse","tool_name":"%s","tool_input":%s,"tool_use_id":"toolu_1"}' "$1" "$2" "$3"
}
expect_raw() { # expect_raw <want> <cwd-json-string> <tool> <tool_input-json>
  local input got
  input=$(hook_json "$2" "$3" "$4")
  got=$(verdict_of "$plain" "$input" "$nojq")
  if [ "$got" = "$1" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL  [%s] %s\n      want %s, got %s\n' "$state" "$input" "$1" "$got"
  fi
}
state="hook input, as sent"
at=$(json_str "$tfrepo")
expect_raw ask "$at" Bash '{"command":"git push","description":"Push"}'
expect_raw pass "$at" Bash '{"command":"git status","description":"Status"}'
# A non-ASCII cwd written as \u escapes (a link to the run's repo).
ln -s "$tfrepo" "$tmp/日本"
expect_raw ask "\"$tmp/\\u65e5\\u672c\"" Bash '{"command":"git push"}'
git -C "$tfrepo" checkout -q main
expect_raw ask "$at" Bash '{"command":["git push"]}'
git -C "$tfrepo" checkout -q GT-000001-login
set_state plan:awaiting-approval
ti="{\"notebook_path\":\"$tfrepo/src/n.ipynb\",\"new_source\":\"x\"}"
expect_raw ask "$at" NotebookEdit "$ti"
ti="{\"notebook_path\":\"$tfrepo/docs/n.ipynb\",\"new_source\":\"x\"}"
expect_raw pass "$at" NotebookEdit "$ti"
ti="{\"edits\":[{\"file_path\":\"$tfrepo/docs/a.md\",\"old_string\":\"a\",\"new_string\":\"b\"}],\"file_path\":\"$tfrepo/src/a.ts\"}"
expect_raw ask "$at" MultiEdit "$ti"
ti="{\"file_path\":\"$tfrepo/docs/\\u65e5.md\",\"edits\":[{\"old_string\":\"\\\"file_path\\\":\\\"src/a.ts\\\"\",\"new_string\":\"b\"}]}"
expect_raw pass "$at" MultiEdit "$ti"
# A path that cannot be read: ask while a run is before Implement.
expect_raw ask "$at" Edit '{"file_path":["x"],"old_string":"a","new_string":"b"}'
set_state implement:in-progress

echo "guard: $pass passed, $fail failed"
[ $fail -eq 0 ]
