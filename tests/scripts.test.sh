#!/usr/bin/env bash
# Tests for the tixforge scripts other than guard.sh. gh is replaced by a stub
# that serves fixture JSON (through jq, as gh --jq would) and records edits.
#
# Usage: bash tests/scripts.test.sh   (also run it with /bin/bash on macOS for 3.2)
set -u

here=$(cd "$(dirname "$0")" && pwd)
scripts="$here/../scripts"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@example.com

pass=0
fail=0
section=""
ok() { pass=$((pass + 1)); }
ng() {
  fail=$((fail + 1))
  printf 'FAIL  [%s] %s\n' "$section" "$1"
}
# eq <want> <got> <what>
eq() { if [ "$1" = "$2" ]; then ok; else ng "$3: want [$1], got [$2]"; fi; }
# has <text> <haystack> <what>
has() { case "$2" in *"$1"*) ok ;; *) ng "$3: [$1] not in [$2]" ;; esac }

repo="$tmp/repo"
git init -q -b main "$repo"
cd "$repo" || exit 1
mkdir -p .tixforge
cat > .tixforge/config.yml << 'EOF'
# tixforge settings (shared, committed)
language: ja   # comment
commands:      # run in order
  test: echo testing && exit 0
  lint: "echo 'a # not a comment' ; exit 1"
ticket:
  tracker: local
repository:
  host: github
  base_branch: main
review:
  required: false
gates: [approach, plan, pr]
EOF
git add -A && git commit -q -m init # .tixforge/.gitignore comes with the first run

# --- all scripts ------------------------------------------------------------
# "$var（" makes bash read the first byte of a multibyte character as part of
# the name (unbound variable under set -u, depending on the locale). Write
# ${var} before non-ASCII text.
section="all scripts"
bad=$(LC_ALL=C grep -nE '\$[A-Za-z_][A-Za-z0-9_]*[^ -~]' "$scripts"/*.sh || true)
eq "" "$bad" "no \$var directly followed by a non-ASCII character"

# --- lib.sh ----------------------------------------------------------------
section="lib.sh cfg"
# shellcheck source=SCRIPTDIR/../scripts/lib.sh
. "$scripts/lib.sh"
eq ja "$(cfg language)" "top-level scalar with comment"
eq local "$(cfg ticket.tracker)" "nested scalar"
eq false "$(cfg review.required)" "review.required"
eq "" "$(cfg ticket.nothing)" "missing key"
eq "approach,plan,pr" "$(cfg_list gates | paste -sd, -)" "cfg_list"
printf 'gates:\n  - plan\n  - pr\n' > "$tmp/block.yml"
eq "plan,pr" "$(cfg_list gates "$tmp/block.yml" | paste -sd, -)" "block list"
eq "test,lint" "$(cfg_map commands | cut -f1 | paste -sd, -)" "command keys in order"
eq "echo testing && exit 0" "$(cfg_map commands | sed -n 1p | cut -f2)" "command value"
# A value quoted only in part keeps its quotes and the rest of the line.
printf 'commands:\n  test: "./run tests.sh" --fast   # note\n  lint: "a # b"   # note\n' > "$tmp/partial.yml"
eq '"./run tests.sh" --fast' "$(cfg_map commands "$tmp/partial.yml" | sed -n 1p | cut -f2)" "partly quoted value"
eq 'a # b' "$(cfg_map commands "$tmp/partial.yml" | sed -n 2p | cut -f2)" "fully quoted value"
# CRLF line ends do not leak into values.
printf 'language: ja\r\nticket:\r\n  tracker: github\r\ngates: [plan, pr]\r\n' > "$tmp/crlf.yml"
eq github "$(cfg ticket.tracker "$tmp/crlf.yml")" "CRLF nested value"
eq ja "$(cfg language "$tmp/crlf.yml")" "CRLF top-level value"
eq "plan,pr" "$(cfg_list gates "$tmp/crlf.yml" | paste -sd, -)" "CRLF list"
cfg_has commands && ok || ng "cfg_has commands"
cfg_has nothing && ng "cfg_has nothing" || ok

# --- ticket-id.sh ----------------------------------------------------------
section="ticket-id.sh"
tid() { bash "$scripts/ticket-id.sh" "$@"; }
eq LT-000123 "$(tid normalize 123)" "a bare number follows tracker: local"
eq GT-000123 "$(tid normalize '#123')" "#N is issue N"
eq GT-000123 "$(tid normalize gt-000123)" "prefix in any case"
eq LT-000007 "$(tid normalize LT-000007)" "canonical"
eq LT-1234567 "$(tid normalize 1234567)" "more than 6 digits"
eq GT-1234567 "$(tid normalize GT-1234567)" "7 digits with a prefix"
tid normalize GT-00123 2> /dev/null
eq 2 $? "too few digits are not padded"
tid normalize GT-0000123 2> /dev/null
eq 2 $? "too many digits"
tid normalize GT-000000 2> /dev/null
eq 2 $? "number zero"
tid normalize 'a b' 2> /dev/null
eq 2 $? "invalid id"
tid normalize T000123 2> /dev/null
eq 2 $? "the old T-prefix form"
has "GT-000123" "$(tid normalize GT-00123 2>&1)" "the error shows the right form"
eq 123 "$(tid number GT-000123)" "number"
eq 8 "$(tid number GT-000008)" "number, not octal"
tid number LT-000001 2> /dev/null
eq 2 $? "a local ticket has no issue number"
cp .tixforge/config.yml "$tmp/keep-conf.yml"
sed 's/tracker: local/tracker: github/' "$tmp/keep-conf.yml" > .tixforge/config.yml
eq GT-000123 "$(tid normalize 123)" "a bare number follows tracker: github"
grep -v 'tracker:' "$tmp/keep-conf.yml" > .tixforge/config.yml
tid normalize 123 2> /dev/null
eq 2 $? "a bare number without a tracker"
cp "$tmp/keep-conf.yml" .tixforge/config.yml

# detect: an id only in an explicit form, or when the whole text is a number.
dt() { tid detect "$@" | sed -n "${n:-1}p"; }
eq "id: none" "$(dt '404 ページを作る')" "a number inside a sentence is not an id"
eq "rest: 404 ページを作る" "$(n=2 dt '404 ページを作る')" "rest keeps the sentence"
eq "id: LT-000404" "$(dt 404)" "the whole text is a number"
eq "id: GT-000012" "$(dt 'GT-000012 の受け入れ条件を直したい')" "explicit id in a sentence"
eq "rest: の受け入れ条件を直したい" "$(n=2 dt 'GT-000012 の受け入れ条件を直したい')" "rest without the id"
eq "id: GT-000007" "$(dt 'ログイン #7 の続き')" "#N in a sentence"
eq "rest: ログイン の続き" "$(n=2 dt 'ログイン #7 の続き')" "rest is tidied"
eq "invalid: gt-12" "$(dt 'gt-12 を直して')" "an explicit id with the wrong digit count"
eq "id: none" "$(dt 'ログイン画面を作りたい')" "no id"
eq "id: none" "$(dt 'v2 の API')" "letters and digits are not an id"

# next: LT ids from .tixforge/ and local branch names only.
eq LT-000001 "$(tid next)" "first ticket"
mkdir -p .tixforge/LT-000005
eq LT-000006 "$(tid next)" "a ticket folder counts"
git branch LT-000009-x
eq LT-000010 "$(tid next)" "a branch name counts"
git branch T2024-release
eq LT-000010 "$(tid next)" "an unrelated branch does not count"
mkdir -p .tixforge/GT-000050
eq LT-000010 "$(tid next)" "a GitHub ticket does not count"
rm -rf .tixforge/LT-000005 .tixforge/GT-000050
git branch -D -q LT-000009-x T2024-release

# exists (LT; GT is tested with the gh stub below)
tid exists LT-000001 > /dev/null
eq 1 $? "no such local ticket"

# --- run-state.sh --------------------------------------------------------------
section="run-state.sh"
st() { bash "$scripts/run-state.sh" "$@"; }
mkdir -p .tixforge/LT-000001 && printf '# LT-000001: A\n\n## 背景\n' > .tixforge/LT-000001/ticket.md
eq .tixforge/LT-000001/state.md "$(st init LT-000001)" "init"
[ -f .tixforge/.gitignore ] && ok || ng "init creates .tixforge/.gitignore"
eq ".tixforge/.gitignore" "$(git status --porcelain --untracked-files=all .tixforge | cut -c4-)" "only .gitignore is visible to git"
git add .tixforge/.gitignore && git commit -q -m gitignore
eq LT-000001 "$(tid exists LT-000001 > /dev/null && echo LT-000001)" "exists: a local ticket"
st init LT-000001 2> /dev/null
eq 3 $? "init twice"
st init T000001 2> /dev/null
eq 2 $? "not a ticket id"
eq research:in-progress "$(st get LT-000001)" "initial Status"
st set LT-000001 Issue '#1' 2> /dev/null
eq 2 $? "Issue is not a header field"
git branch LT-000001-a
eq LT-000001-a "$(st set LT-000001 Branch LT-000001-a)" "set Branch"
st set LT-000001 Status implement:typo 2> /dev/null
eq 2 $? "invalid Status"
st set LT-000001 Updated x 2> /dev/null
eq 2 $? "Updated is not settable"
eq plan:awaiting-approval "$(st set LT-000001 Status plan:awaiting-approval)" "set Status"
st set LT-000001 Status implement:in-progress > /dev/null
grep -q '^## Implementation Log' .tixforge/LT-000001/state.md && ok || ng "sections kept"
eq "$(printf 'LT-000001\timplement:in-progress\tLT-000001-a')" "$(st list)" "list"
st get LT-000404 2> /dev/null
eq 1 $? "no such run"
eq pr:ready-to-merge "$(st set LT-000001 Status pr:ready-to-merge)" "ready-to-merge is a Status"
st set LT-000001 Status implement:in-progress > /dev/null

# rewind: later sections move to history/, the target gets a note.
mkdir -p .tixforge/LT-000009
bash "$scripts/run-state.sh" init LT-000009 > /dev/null
f9=.tixforge/LT-000009/state.md
for sec in Research Approach Plan 'Implementation Log' Review PR; do
  awk -v s="## $sec" -v b="body of $sec" '$0 == s { print; print b; skip = 1; next } skip && /^<!--/ { skip = 0; next } { skip = 0; print }' "$f9" > "$tmp/s9" && cat "$tmp/s9" > "$f9"
done
st set LT-000009 Status review:in-progress > /dev/null
h=$(st rewind LT-000009 plan --reason "分割を変える")
has ".tixforge/LT-000009/history/" "$h" "rewind prints the history file"
eq plan:in-progress "$(st get LT-000009)" "rewind sets the Status"
has "body of Approach" "$(cat "$f9")" "earlier sections stay"
case "$(cat "$f9")" in *"body of Plan"* | *"body of Review"*) ng "the target and later sections leave state.md" ;; *) ok ;; esac
has "body of Plan" "$(cat "$h")" "they are in the history file"
has "Status before: review:in-progress" "$(cat "$h")" "history records the Status before"
has "> 巻き戻し（" "$(cat "$f9")" "the target section notes the rewind"
has "分割を変える" "$(cat "$f9")" "with the reason"
sleep 1
awk '$0 == "## Implementation Log" { print; print "kept log"; next } { print }' "$f9" > "$tmp/s9" && cat "$tmp/s9" > "$f9"
st rewind LT-000009 approach --keep-log > /dev/null
has "kept log" "$(cat "$f9")" "--keep-log keeps the Implementation Log"
awk '$0 == "## Review" { print; print "a review"; next } { print }' "$f9" > "$tmp/s9" && cat "$tmp/s9" > "$f9"
st rewind LT-000009 implement 2> /dev/null
eq 2 $? "cannot rewind forward (approach -> implement)"
eq approach:in-progress "$(st get LT-000009)" "a refused rewind leaves the Status"
st set LT-000009 Status review:in-progress > /dev/null
st rewind LT-000009 implement > /dev/null
has "kept log" "$(cat "$f9")" "rewinding to implement keeps the log"
case "$(cat "$f9")" in *"a review"*) ng "rewinding to implement moves Review" ;; *) ok ;; esac
st rewind LT-000009 review 2> /dev/null
eq 2 $? "cannot rewind to review"
# Rewinding to the current phase is a normal use (redo the Plan).
st set LT-000009 Status plan:awaiting-approval > /dev/null
st rewind LT-000009 plan > /dev/null && ok || ng "rewind to the current phase"
# "## " inside a fence is not a section: the whole Approach moves.
st set LT-000009 Status plan:in-progress > /dev/null
awk '$0 == "## Approach" { print; print "fenced start"; print "```markdown"; print "## 背景"; print "fenced tail"; print "```"; print "after fence"; next } { print }' "$f9" > "$tmp/s9" && cat "$tmp/s9" > "$f9"
h=$(st rewind LT-000009 approach --reason 'C:\temp\new')
case "$(cat "$f9")" in *"fenced"* | *"after fence"* | *"## 背景"*) ng "a fenced ## line ends the section" ;; *) ok ;; esac
has "after fence" "$(cat "$h")" "the whole fenced Approach is in the history"
has 'C:\temp\new' "$(cat "$h")" "backslashes of the reason are kept (history)"
has 'C:\temp\new' "$(cat "$f9")" "backslashes of the reason are kept (note)"
# Two rewinds in the same second get two history files.
h1=$(st rewind LT-000009 approach --reason one)
h2=$(st rewind LT-000009 approach --reason two)
[ "$h1" != "$h2" ] && [ -f "$h1" ] && [ -f "$h2" ] && ok || ng "same-second rewinds keep both history files ($h1, $h2)"
has "Reason: one" "$(cat "$h1")" "the first history file is not overwritten"
st set LT-000009 Status done > /dev/null
st rewind LT-000009 plan 2> /dev/null
eq 4 $? "a done run is not rewound"
rm -rf .tixforge/LT-000009

# --- project-status.sh -------------------------------------------------------------
section="project-status.sh"
out=$(bash "$scripts/project-status.sh")
has "tracker=local" "$out" "config"
has "gates=approach,plan,pr" "$out" "gates"
has "LT-000001: Status implement:in-progress" "$out" "open run"
out=$(cd "$tmp" && bash "$scripts/project-status.sh")
eq 0 $? "outside a repo exits 0"
has "config.yml が無い" "$out" "no config"
cp .tixforge/config.yml "$tmp/keep-gates.yml"
sed 's/^gates: .*/gates: []/' "$tmp/keep-gates.yml" > .tixforge/config.yml
has "gates=[]（pr のみ）" "$(bash "$scripts/project-status.sh")" "explicit empty gates"
grep -v '^gates:' "$tmp/keep-gates.yml" > .tixforge/config.yml
has "gates=（未設定）" "$(bash "$scripts/project-status.sh")" "missing gates"
cp "$tmp/keep-gates.yml" .tixforge/config.yml

# --- session-start.sh ------------------------------------------------------
section="session-start.sh"
git switch -q LT-000001-a
out=$(printf '{"source":"compact","cwd":"%s"}' "$repo" | bash "$scripts/session-start.sh")
has "run LT-000001" "$out" "run on this branch"
has "skills/dev/run.md" "$out" "tells to re-read run.md"
case "$out" in *"skills/dev/pr.md"*) ng "pr.md only in the PR phase" ;; *) ok ;; esac
bash "$scripts/run-state.sh" set LT-000001 Status pr:awaiting-review > /dev/null
out=$(printf '{"source":"compact","cwd":"%s"}' "$repo" | bash "$scripts/session-start.sh")
has "skills/dev/pr.md" "$out" "the PR phase also re-reads pr.md"
bash "$scripts/run-state.sh" set LT-000001 Status implement:in-progress > /dev/null
git switch -q main
out=$(printf '{"source":"compact","cwd":"%s"}' "$repo" | bash "$scripts/session-start.sh")
eq "" "$out" "no run on main"
bash "$scripts/run-state.sh" set LT-000001 Status approach:in-progress > /dev/null
out=$(printf '{"source":"compact","cwd":"%s"}' "$repo" | bash "$scripts/session-start.sh")
has "run LT-000001" "$out" "the only run before Implement, with no branch yet"
bash "$scripts/run-state.sh" init LT-000002 > /dev/null
out=$(printf '{"source":"compact","cwd":"%s"}' "$repo" | bash "$scripts/session-start.sh")
has "複数" "$out" "several runs before Implement: ask which"
has "LT-000001 LT-000002" "$out" "both are listed"
rm -rf .tixforge/LT-000002
bash "$scripts/run-state.sh" set LT-000001 Status implement:in-progress > /dev/null

# --- statusline.sh ---------------------------------------------------------
section="statusline.sh"
sl() { printf '%s' "$1" | bash "$scripts/statusline.sh"; }
git switch -q LT-000001-a
eq "LT-000001 · implement:in-progress" "$(sl "{\"cwd\":\"$repo\"}")" "the run on this branch"
eq "LT-000001 · implement:in-progress" "$(sl "{\"workspace\":{\"current_dir\":\"$repo\"}}")" "workspace.current_dir when there is no cwd"
mkdir -p sub
eq "LT-000001 · implement:in-progress" "$(sl "{\"cwd\":\"$repo/sub\"}")" "from a subdirectory"
rmdir sub
git switch -q main
eq "" "$(sl "{\"cwd\":\"$repo\"}")" "nothing on main with no run before Implement"
bash "$scripts/run-state.sh" set LT-000001 Status plan:awaiting-approval > /dev/null
eq "LT-000001 · plan:awaiting-approval" "$(sl "{\"cwd\":\"$repo\"}")" "the only run before Implement"
bash "$scripts/run-state.sh" init LT-000002 > /dev/null
eq "LT-000001 · plan:awaiting-approval (+1)" "$(sl "{\"cwd\":\"$repo\"}")" "several runs before Implement"
rm -rf .tixforge/LT-000002
bash "$scripts/run-state.sh" set LT-000001 Status implement:in-progress > /dev/null
eq "" "$(sl "{\"cwd\":\"$tmp\"}")" "nothing outside a repository"
eq "" "$(sl '{}')" "nothing without a directory"
eq "" "$(sl "{\"cwd\":\"$repo/missing\"}")" "nothing for a missing directory"

# --- verify.sh -------------------------------------------------------------
section="verify.sh"
echo wip > wip.txt
out=$(bash "$scripts/verify.sh")
code=$?
eq 1 $code "a failing command"
has "Verification @ $(git rev-parse --short HEAD)+dirty: test pass, lint fail" "$out" "result line"
has "log lint:" "$out" "log of the failure"
has "a # not a comment" "$(cat "$(git rev-parse --absolute-git-dir)/tixforge/verify/lint.log")" "quoted # kept"
git stash -q -u
sed 's/exit 1"/exit 0"/' .tixforge/config.yml > "$tmp/c" && cat "$tmp/c" > .tixforge/config.yml
git commit -q -am pass
out=$(bash "$scripts/verify.sh")
eq 0 $? "all pass"
eq "Verification @ $(git rev-parse --short HEAD): test pass, lint pass" "$out" "clean tree"
# A command that rewrites a tracked file: the commit was not what the later
# commands checked.
printf 'language: ja\ncommands:\n  fmt: echo x >> wip-tracked.txt\n  test: "true"\n' > .tixforge/config.yml
echo a > wip-tracked.txt && git add wip-tracked.txt .tixforge/config.yml && git commit -q -m tracked
eq "" "$(git status --porcelain)" "the tree is clean before verifying"
out=$(bash "$scripts/verify.sh")
eq 0 $? "a rewriting command still passes"
has "Verification @ $(git rev-parse --short HEAD)+dirty: fmt pass, test pass" "$out" "+dirty when a command changed the tree"
has " M wip-tracked.txt" "$out" "the changed file is listed"
git reset -q --hard HEAD~1
git stash pop -q
printf 'language: ja\ncommands: {}\n' > "$tmp/empty.yml"
cp .tixforge/config.yml "$tmp/keep.yml"
cp "$tmp/empty.yml" .tixforge/config.yml
has "検証コマンドなし" "$(bash "$scripts/verify.sh")" "commands: {}"
printf 'language: ja\n' > .tixforge/config.yml
bash "$scripts/verify.sh" 2> /dev/null
eq 3 $? "no commands key"
cp "$tmp/keep.yml" .tixforge/config.yml

# --- review-input.sh -------------------------------------------------------
section="review-input.sh"
git switch -q LT-000001-a
echo change > file.txt && git add file.txt && git commit -q -m change
paths=$(bash "$scripts/review-input.sh" LT-000001 main)
diff_file=$(printf '%s\n' "$paths" | sed -n 1p)
has "+change" "$(cat "$diff_file")" "diff"
has "/.git/tixforge/review/LT-000001/" "$diff_file" "outside .tixforge"
eq 3 "$(printf '%s\n' "$paths" | grep -c .)" "three paths without --since"
# --since writes the change after a given commit as delta.patch.
since=$(git rev-parse HEAD)
echo more > more.txt && git add more.txt && git commit -q -m more
paths=$(bash "$scripts/review-input.sh" LT-000001 main --since "$since")
delta=$(printf '%s\n' "$paths" | sed -n 4p)
has "delta.patch" "$delta" "delta path"
has "+more" "$(cat "$delta")" "delta has the new change"
case "$(cat "$delta")" in *"+change"*) ng "delta has only the new change" ;; *) ok ;; esac
has "+change" "$(cat "$(printf '%s\n' "$paths" | sed -n 1p)")" "full diff still has everything"
bash "$scripts/review-input.sh" LT-000001 main > /dev/null
[ -f "$delta" ] && ng "delta removed without --since" || ok
bash "$scripts/review-input.sh" LT-000001 main --since nope 2> /dev/null
eq 2 $? "unknown --since commit"
# A local base behind origin/<base>: others' commits there are not this run's.
git switch -q main
echo other > other.txt && git add other.txt && git commit -q -m other
git update-ref refs/remotes/origin/main HEAD
git reset -q --hard HEAD~1
git switch -q LT-000001-a
git merge -q --no-edit origin/main
paths=$(bash "$scripts/review-input.sh" LT-000001 main)
case "$(cat "$(printf '%s\n' "$paths" | sed -n 1p)")" in *"+other"*) ng "stale local base: others' commit excluded" ;; *) ok ;; esac
has "+change" "$(cat "$(printf '%s\n' "$paths" | sed -n 1p)")" "stale local base: own change kept"
git update-ref -d refs/remotes/origin/main
git switch -q main

# --- ticket-hash.sh --------------------------------------------------------
section="ticket-hash.sh"
th() { bash "$scripts/ticket-hash.sh" "$@"; }
h1=$(printf '## A\nx\n' | th hash "Title")
h2=$(printf '## A\r\nx\r\n\n  \n' | th hash " Title ")
eq "$h1" "$h2" "CRLF and trailing blanks do not change the hash"
h3=$(printf '## A\n x\n' | th hash "Title")
[ "$h1" != "$h3" ] && ok || ng "inner spacing changes the hash"
h4=$(printf '## A\nx\n' | th hash "Title2")
[ "$h1" != "$h4" ] && ok || ng "the title changes the hash"
body=$(printf '> note\n\n<!-- tixforge:hash:abc123abc123 -->\r\n<!-- tixforge:ticket:start -->\r\n## A\r\nx\r\n<!-- tixforge:ticket:end -->\r\n')
eq "$(printf '## A\nx')" "$(printf '%s' "$body" | th extract)" "extract"
eq abc123abc123 "$(printf '%s' "$body" | th stored)" "stored"
printf 'no markers\n' | th extract > /dev/null
eq 3 $? "extract without markers"

# --- gh stub ---------------------------------------------------------------
# Serves $GH_DIR/issue-<n>.json and $GH_DIR/pr.json; writes edits to
# $GH_DIR/calls. `issue edit --body-file f` also updates the fixture body.
bin="$tmp/bin"
mkdir -p "$bin"
GH_DIR="$tmp/gh"
mkdir -p "$GH_DIR"
export GH_DIR
cat > "$bin/gh" << 'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH_DIR/calls"
jqf=""; args=()
while [ $# -gt 0 ]; do
  case $1 in --jq) jqf=$2; shift 2 ;; --json) shift 2 ;; *) args+=("$1"); shift ;; esac
done
set -- "${args[@]}"
case "$1 $2" in
  "issue view") jq -r "$jqf" "$GH_DIR/issue-$3.json" ;;
  "api user") echo me ;;
  "api repos/"*)   # .../issues/<n>: an issue, or a PR when the fixture has pull_request; .../issues/<n>/events
    case $2 in
      */events) n=${2%/events}; n=${n##*/}; jq -r "(.events // []) | $jqf" "$GH_DIR/issue-$n.json" ;;
      *) f="$GH_DIR/issue-${2##*/}.json"
         if [ -f "$f" ]; then jq -r "$jqf" "$f"; else echo "gh: Not Found (HTTP 404)" >&2; exit 1; fi ;;
    esac ;;
  "auth status") [ -z "${GH_NO_AUTH:-}" ] ;;
  "repo view") echo o/r ;;
  "label list") cat "$GH_DIR/labels" 2>/dev/null || true ;;
  "label create") echo "$3" >> "$GH_DIR/labels" ;;
  "issue comment")
    n=$3; shift 3
    while [ $# -gt 0 ]; do
      case $1 in
        --body-file) jq --rawfile b "$2" '.comments += [{body: $b}]' "$GH_DIR/issue-$n.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-$n.json"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
  "issue create")
    echo "https://github.com/o/r/issues/42" ;;
  "issue edit")
    n=$3; shift 3
    while [ $# -gt 0 ]; do
      case $1 in
        --body-file) jq --rawfile b "$2" '.body = $b' "$GH_DIR/issue-$n.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-$n.json"; shift 2 ;;
        --title) jq --arg t "$2" '.title = $t' "$GH_DIR/issue-$n.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-$n.json"; shift 2 ;;
        --remove-label) jq --arg l "$2" '.labels |= map(select(.name != $l))' "$GH_DIR/issue-$n.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-$n.json"; shift 2 ;;
        *) shift ;;
      esac
    done ;;
  *) echo "stub gh: unexpected $*" >&2; exit 1 ;;
esac
EOF
chmod +x "$bin/gh"
PATH="$bin:$PATH"

# issue <n> <title> <body-file> [state] [reason] [labels-json]
issue() {
  jq -n --arg t "$2" --rawfile b "$3" --arg s "${4:-OPEN}" --arg r "${5:-}" --argjson l "${6:-[]}" \
    '{title: $t, body: $b, state: $s, stateReason: $r, labels: $l, assignees: [], comments: [], closedByPullRequestsReferences: [], events: []}' \
    > "$GH_DIR/issue-$1.json"
}

# --- issue-sync.sh ---------------------------------------------------------
section="issue-sync.sh"
is() { bash "$scripts/issue-sync.sh" "$@"; }
cat > "$tmp/draft.md" << 'EOF'
# <ticket-id>: ログイン

## 背景
ログインしたい

## 受け入れ条件
- [ ] ログインできる
EOF
is body "$tmp/draft.md" > "$tmp/body42"
issue 42 "ログイン" "$tmp/body42" # what gh issue create makes
out=$(is create "$tmp/draft.md")
has "number: 42" "$out" "create prints the number"
has "id: GT-000042" "$out" "create prints the id"
has "file: .tixforge/GT-000042/ticket.md" "$out" "create makes the working copy"
has "--label tixforge:todo" "$(cat "$GH_DIR/calls")" "create labels tixforge:todo"
eq "# GT-000042: ログイン" "$(sed -n 1p .tixforge/GT-000042/ticket.md)" "working copy title line"
is create "$tmp/draft.md" > /dev/null 2>&1
eq 6 $? "create refuses an existing ticket folder"
rm -rf .tixforge/GT-000042
has "<!-- tixforge:ticket:start -->" "$(cat "$tmp/body42")" "body has markers"
has "この issue の本文は" "$(cat "$tmp/body42")" "notice in the document language"
issue 42 "ログイン" "$tmp/body42"
eq in-sync "$(is check 42 | sed -n 1p)" "fresh issue is in sync"
eq issue "$(tid exists GT-000042)" "exists: an issue"
jq -n '{title: "a PR", pull_request: {}}' > "$GH_DIR/issue-60.json"
eq pull-request "$(tid exists '#60')" "exists: the number is a pull request"
tid exists GT-000061 > /dev/null
eq 1 $? "exists: no such issue"
cp .tixforge/config.yml "$tmp/keep-lang.yml"
sed 's/^language: ja.*/language: en/' "$tmp/keep-lang.yml" > .tixforge/config.yml
has "This issue body is synced" "$(is body "$tmp/draft.md")" "notice in English"
sed 's/^language: ja.*/language: fr/' "$tmp/keep-lang.yml" > .tixforge/config.yml
has "This issue body is synced" "$(is body "$tmp/draft.md")" "a language without messages falls back to English"
cp "$tmp/keep-lang.yml" .tixforge/config.yml

out=$(is pull 42 .tixforge/GT-000042/ticket.md)
has "created" "$out" "pull creates the working copy"
eq "# GT-000042: ログイン" "$(sed -n 1p .tixforge/GT-000042/ticket.md)" "title line"
eq 0 "$(grep -c '^Issue:' .tixforge/GT-000042/ticket.md)" "no Issue line: the id carries the number"
eq "$(
  ticket_body() { awk '/^## / { on = 1 } on' "$1"; }
  ticket_body "$tmp/draft.md"
)" \
  "$(awk '/^## / { on = 1 } on' .tixforge/GT-000042/ticket.md)" "ticket copied verbatim"
has "unchanged" "$(is pull 42 .tixforge/GT-000042/ticket.md)" "pull again"

# Edited on GitHub: the hash no longer matches.
sed 's/ログインしたい/ログインしたい（直接編集）/' "$tmp/body42" > "$tmp/edited"
issue 42 "ログイン" "$tmp/edited" OPEN "" '[{"name":"tixforge:out-of-sync"}]'
eq edited "$(is check 42 | sed -n 1p)" "direct edit detected"
issue 42 "ログイン（改）" "$tmp/body42"
eq edited "$(is check 42 | sed -n 1p)" "direct title edit detected"
issue 42 "ログイン" "$tmp/edited" OPEN "" '[{"name":"tixforge:out-of-sync"}]'
is pull 42 .tixforge/GT-000042/ticket.md > /dev/null 2>&1
eq 4 $? "pull refuses an edited issue"
before=$(cat .tixforge/GT-000042/ticket.md)
is pull 42 .tixforge/GT-000042/ticket.md --accept-edited --dry-run | grep -q '直接編集' && ok || ng "dry run shows the diff"
eq "$before" "$(cat .tixforge/GT-000042/ticket.md)" "dry run does not write"
is pull 42 .tixforge/GT-000042/ticket.md --accept-edited | grep -q '直接編集' && ok || ng "pull --accept-edited shows the diff"
is push 42 .tixforge/GT-000042/ticket.md > /dev/null 2>&1
eq 4 $? "push refuses an edited issue"
out=$(is push 42 .tixforge/GT-000042/ticket.md --force)
has "updated" "$out" "push --force rehashes"
has "removed label: tixforge:out-of-sync" "$out" "push removes out-of-sync"
eq in-sync "$(is check 42 | sed -n 1p)" "in sync after adopting"

# Local edit (/tixforge:ticket edit) then push.
sed 's/ログインできる/ログインできる\n- [ ] ログアウトできる/' .tixforge/GT-000042/ticket.md > "$tmp/t" && cat "$tmp/t" > .tixforge/GT-000042/ticket.md
has "updated" "$(is push 42 .tixforge/GT-000042/ticket.md)" "push a local edit"
has "ログアウトできる" "$(jq -r .body "$GH_DIR/issue-42.json")" "issue has the edit"
eq in-sync "$(is check 42 | sed -n 1p)" "in sync after push"
has "unchanged" "$(is push 42 .tixforge/GT-000042/ticket.md)" "push again"

# Markers removed on GitHub.
printf 'just text\n' > "$tmp/nomark"
issue 43 "x" "$tmp/nomark"
eq no-markers "$(is check 43 | sed -n 1p)" "no markers"
is pull 43 .tixforge/GT-000043/ticket.md > /dev/null 2>&1
eq 3 $? "pull without markers"

# An issue made before hashes.
grep -v 'tixforge:hash' "$tmp/body42" > "$tmp/nohash"
issue 44 "ログイン" "$tmp/nohash"
eq no-hash "$(is check 44 | sed -n 1p)" "no hash"
has "created" "$(is pull 44 .tixforge/GT-000044/ticket.md)" "pull an issue without a hash"

# Canceled issue: Status / Reason come back.
sed '1s/.*/# <ticket-id>: やめた/' "$tmp/draft.md" > "$tmp/draft45"
is body "$tmp/draft45" > "$tmp/body45"
issue 45 "やめた" "$tmp/body45" CLOSED NOT_PLANNED
jq '.comments = [{"body":"Canceled by tixforge: 優先度が下がった"}]' "$GH_DIR/issue-45.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-45.json"
eq "closed_as: canceled" "$(is check 45 | sed -n 2p)" "canceled by tixforge (comment)"
is pull 45 .tixforge/GT-000045/ticket.md > /dev/null
eq 0 "$(grep -c '^Status:' .tixforge/GT-000045/ticket.md)" "pull writes no Status line: the issue says it"
issue 45 "やめた" "$tmp/body45" OPEN ""
eq "closed_as: open" "$(is check 45 | sed -n 2p)" "reopened: open again"
issue 45 "やめた" "$tmp/body45" CLOSED NOT_PLANNED '[{"name":"tixforge:canceled"}]'
eq "closed_as: canceled" "$(is check 45 | sed -n 2p)" "canceled by label"
issue 45 "やめた" "$tmp/body45" CLOSED COMPLETED '[{"name":"tixforge:in-review"}]'
eq "closed_as: unexpected" "$(is check 45 | sed -n 2p)" "closed by hand"
jq '.events = [{"event":"closed","commit_id":"abc123"}]' "$GH_DIR/issue-45.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-45.json"
eq "closed_as: completed" "$(is check 45 | sed -n 2p)" "closed by a commit (Closes in a commit reaching the default branch)"
issue 45 "やめた" "$tmp/body45" CLOSED COMPLETED '[{"name":"tixforge:merged"}]'
eq "closed_as: completed" "$(is check 45 | sed -n 2p)" "merged label"
issue 45 "やめた" "$tmp/body45" CLOSED COMPLETED
jq '.closedByPullRequestsReferences = [{"number":9}]' "$GH_DIR/issue-45.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-45.json"
eq "closed_as: completed" "$(is check 45 | sed -n 2p)" "closed by a PR"

# Optimistic lock: someone else pushed after this copy was fetched.
issue 46 "ログイン" "$tmp/body42"
is pull 46 .tixforge/GT-000046/ticket.md > /dev/null
cp .tixforge/GT-000046/ticket.md "$tmp/mine46"
sed 's/ログインしたい/他の人の変更/' .tixforge/GT-000046/ticket.md > "$tmp/theirs46" && cp "$tmp/theirs46" .tixforge/GT-000046/ticket.md
is push 46 .tixforge/GT-000046/ticket.md > /dev/null # the other person's push (their copy is fresh)
cp "$tmp/mine46" .tixforge/GT-000046/ticket.md
bash "$scripts/ticket-hash.sh" stored < "$tmp/body42" > .tixforge/GT-000046/.issue-hash # my copy came from the old version
sed 's/ログインできる/私の変更/' "$tmp/mine46" > .tixforge/GT-000046/ticket.md
is push 46 .tixforge/GT-000046/ticket.md > /dev/null 2>&1
eq 5 $? "push refuses: the issue changed since it was fetched"
has "他の人の変更" "$(jq -r .body "$GH_DIR/issue-46.json")" "the other person's change is kept"
eq "local: differs" "$(is check 46 .tixforge/GT-000046/ticket.md | sed -n 3p)" "check: the copy is not the last synced version"
is pull 46 .tixforge/GT-000046/ticket.md > /dev/null
eq "local: same" "$(is check 46 .tixforge/GT-000046/ticket.md | sed -n 3p)" "check: after pull the copy is the synced version"
eq "local: missing" "$(is check 46 "$tmp/none.md" | sed -n 3p)" "check: no copy"
eq "assignees: " "$(is check 46 | tail -1)" "check: no assignee"
jq '.assignees = [{"login":"me"},{"login":"someone"}]' "$GH_DIR/issue-46.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-46.json"
eq "assignees: me,someone" "$(is check 46 | tail -1)" "check: assignees on the last line"

# adopt: an issue written on GitHub (issue form), then written back keeping the original.
printf '### 背景\n\nフォームから\n\n### 要件\n\n- 何か\n\n### 未決事項\n\n_No response_\n' > "$tmp/form"
issue 47 "フォームの issue" "$tmp/form" OPEN "" '[{"name":"tixforge:todo"}]'
out=$(is adopt 47 .tixforge/GT-000047/ticket.md)
has "adopted" "$out" "adopt"
eq "# GT-000047: フォームの issue" "$(sed -n 1p .tixforge/GT-000047/ticket.md)" "adopt: title line"
has "## 背景" "$(cat .tixforge/GT-000047/ticket.md)" "adopt: ### becomes ##"
has "なし" "$(cat .tixforge/GT-000047/ticket.md)" "adopt: _No response_ becomes なし"
is adopt 42 "$tmp/x.md" 2> /dev/null
eq 2 $? "adopt refuses an issue tixforge wrote"
out=$(is push 47 .tixforge/GT-000047/ticket.md --force --keep-original)
has "commented: the original body" "$out" "keep-original comments first"
has "フォームから" "$(jq -r '.comments[0].body' "$GH_DIR/issue-47.json")" "the original body is in the comment"
eq in-sync "$(is check 47 | sed -n 1p)" "adopted issue is in sync"

# --- issue-label.sh --------------------------------------------------------
section="issue-label.sh"
il() { bash "$scripts/issue-label.sh" "$@"; }
jq '.labels = [{"name":"tixforge:todo"},{"name":"bug"}] | .assignees = []' "$GH_DIR/issue-42.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-42.json"
: > "$GH_DIR/calls"
has "tixforge:in-progress" "$(il 42 start)" "start"
has "--remove-label tixforge:todo --add-label tixforge:in-progress --add-assignee @me" "$(tail -1 "$GH_DIR/calls")" "start edits"
jq '.assignees = [{"login":"someone"}]' "$GH_DIR/issue-42.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-42.json"
il 42 start 2> /dev/null
eq 4 $? "someone else is assigned"
il 42 start --force > /dev/null
eq 0 $? "start --force"
jq '.assignees = [{"login":"me"}] | .labels = [{"name":"tixforge:in-review"}]' "$GH_DIR/issue-42.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-42.json"
il 42 reset > /dev/null
has "--remove-label tixforge:in-review --add-label tixforge:todo --remove-assignee @me" "$(tail -1 "$GH_DIR/calls")" "reset edits"
jq '.state = "CLOSED"' "$GH_DIR/issue-42.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-42.json"
il 42 review 2> /dev/null
eq 3 $? "closed issue"
jq '.labels = [{"name":"tixforge:in-review"},{"name":"tixforge:out-of-sync"}]' "$GH_DIR/issue-42.json" > "$GH_DIR/t" && mv "$GH_DIR/t" "$GH_DIR/issue-42.json"
il 42 done > /dev/null
eq 0 $? "done applies to a closed issue"
has "--remove-label tixforge:in-review --add-label tixforge:done" "$(tail -1 "$GH_DIR/calls")" "done: one status label, out-of-sync kept"
il 42 canceled > /dev/null
eq 0 $? "canceled applies to a closed issue"
il 42 merged > /dev/null
has "--add-label tixforge:merged" "$(tail -1 "$GH_DIR/calls")" "merged"
il 42 done --force 2> /dev/null
eq 2 $? "--force is only for start"
printf 'tixforge:todo\nbug\n' > "$GH_DIR/labels"
out=$(il setup)
has "tixforge:in-progress" "$out" "setup creates the missing labels"
case "$out" in *"tixforge:todo "* | *"tixforge:todo") ng "setup skips an existing label" ;; *) ok ;; esac
eq "labels: all present" "$(il setup)" "setup again"

# --- github-preflight.sh ---------------------------------------------------
section="github-preflight.sh"
eq "ok: o/r" "$(bash "$scripts/github-preflight.sh")" "ok"
GH_NO_AUTH=1 bash "$scripts/github-preflight.sh" > /dev/null
eq 4 $? "not logged in"
# A PATH with bash only: gh may live in /usr/bin (GitHub's Ubuntu runners).
nogh="$tmp/nogh-bin"
mkdir -p "$nogh"
ln -s "$(command -v bash)" "$nogh/bash"
PATH="$nogh" "$nogh/bash" "$scripts/github-preflight.sh" > /dev/null
eq 3 $? "no gh"

# --- pr-status.sh ----------------------------------------------------------
section="pr-status.sh"
prs() { TF_PR_JSON="$tmp/pr.json" bash "$scripts/pr-status.sh" x | sed -n 1p; }
# pr <state> <mergeable> <reviewDecision> <latestReviews-json> <checks-json>
pr() {
  jq -n --arg s "$1" --arg m "$2" --arg d "$3" --argjson r "$4" --argjson c "$5" \
    '{url: "https://github.com/o/r/pull/9", state: $s, isDraft: false, mergeable: $m, reviewDecision: $d, latestReviews: $r, statusCheckRollup: $c}' > "$tmp/pr.json"
}
ok_check='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"SUCCESS"}]'
bad_check='[{"__typename":"CheckRun","name":"test","status":"COMPLETED","conclusion":"FAILURE"}]'
run_check='[{"__typename":"CheckRun","name":"test","status":"IN_PROGRESS","conclusion":""}]'
approved='[{"state":"APPROVED","author":{"login":"a"}}]'
pr MERGED MERGEABLE "" '[]' "$ok_check"
eq merged "$(prs)" "merged"
pr CLOSED MERGEABLE "" '[]' "$ok_check"
eq closed "$(prs)" "closed"
pr OPEN CONFLICTING APPROVED "$approved" "$ok_check"
eq conflict "$(prs)" "conflict"
pr OPEN MERGEABLE APPROVED "$approved" "$bad_check"
eq ci_failing "$(prs)" "ci failing"
pr OPEN MERGEABLE CHANGES_REQUESTED '[{"state":"CHANGES_REQUESTED","author":{"login":"a"}}]' "$ok_check"
eq changes_requested "$(prs)" "changes requested"
pr OPEN MERGEABLE APPROVED "$approved" "$ok_check"
eq approved "$(prs)" "approved"
pr OPEN MERGEABLE "" '[]' "$ok_check"
eq ready "$(prs)" "ready without review"
pr OPEN MERGEABLE "" '[]' '[]'
eq ready "$(prs)" "ready, no checks"
pr OPEN MERGEABLE "" '[]' "$run_check"
eq pending "$(prs)" "checks running"
pr OPEN UNKNOWN "" '[]' "$ok_check"
eq pending "$(prs)" "mergeability unknown"
# A draft cannot be merged: never ready or approved.
pr OPEN MERGEABLE APPROVED "$approved" "$ok_check"
jq '.isDraft = true' "$tmp/pr.json" > "$tmp/pr2.json" && mv "$tmp/pr2.json" "$tmp/pr.json"
eq pending "$(prs)" "draft"
has "draft: true" "$(TF_PR_JSON="$tmp/pr.json" bash "$scripts/pr-status.sh" x)" "draft detail"
# No check at all is reported as such, so the caller can tell it from success.
pr OPEN MERGEABLE "" '[]' '[]'
has "ci: none" "$(TF_PR_JSON="$tmp/pr.json" bash "$scripts/pr-status.sh" x)" "no checks detail"
pr OPEN MERGEABLE "" '[]' "$ok_check"
has "ci: success" "$(TF_PR_JSON="$tmp/pr.json" bash "$scripts/pr-status.sh" x)" "checks detail"

echo "scripts: $pass passed, $fail failed"
[ $fail -eq 0 ]
