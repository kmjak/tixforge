#!/usr/bin/env bash
# Move a project from the flow plugin (1.x) to tixforge (2.x). Run it once
# at the root of a project that used flow. Without --apply it only prints
# what it would do.
#
#   migrate-from-flow.sh [--apply] [--github]
#
# Local (always):
#   docs/flow.config.yml       -> .tixforge/config.yml (default_branch becomes
#                                 base_branch; prefix and pad are dropped)
#   docs/tickets/<id>.md       -> .tixforge/<new id>/ticket.md: GT-<n> when the
#                                 ticket has "Issue: #n", else LT-<number of id>
#   docs/flow/<id>/main.md     -> .tixforge/<new id>/state.md (Ticket and Issue
#                                 rows dropped); docs/flow/.active removed
#   .github/workflows/flow-*.yml, .github/flow/ -> the tixforge-* versions
#   .tixforge/.gitignore       created; tracked old files are git rm'd, so the
#                                 result is one commit for the user to review
# GitHub (--github, needs gh): renames the flow:* labels to tixforge:*,
#   creates the new ones, rewrites the markers in the body of every tixforge
#   issue, and labels closed ones tixforge:done / tixforge:canceled.
#
# Branch names of runs in progress (T000123-login) are kept: the run's state
# says which branch is its own. Exit: 0 ok, 2 usage, 3 nothing to migrate.
set -uo pipefail
here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=SCRIPTDIR/lib.sh
. "$here/lib.sh"

apply="" github=""
for a in "$@"; do
  case $a in --apply) apply=1 ;; --github) github=1 ;; *)
    grep '^#   [a-z]' "$0" | sed 's/^#   //' >&2
    exit 2
    ;;
  esac
done

top=$(flow_top)
cd "$top" || exit 1
old_conf=docs/flow.config.yml
[ -f "$old_conf" ] || [ -d docs/flow ] || [ -d docs/tickets ] || {
  echo "flow のファイルが見つからない（docs/flow.config.yml・docs/flow/・docs/tickets/）"
  exit 3
}

say() { printf '%s %s\n' "$([ -n "$apply" ] && echo '•' || echo '(dry-run)')" "$*"; }
run() {
  [ -n "$apply" ] && "$@"
  return 0
}
tracked() { git ls-files --error-unmatch "$1" > /dev/null 2>&1; }

prefix=T
if [ -f "$old_conf" ]; then
  p=$(cfg ticket.prefix "$old_conf")
  [ -n "$p" ] && prefix=$p
fi

# new_id <old id> <ticket file or empty>: GT-<issue> or LT-<number>.
new_id() {
  local n=""
  [ -n "$2" ] && [ -f "$2" ] && n=$(grep -Eo -m1 '^Issue:[[:space:]]*#[0-9]+' "$2" | tr -dc '0-9')
  if [ -n "$n" ]; then
    printf 'GT-%06d\n' "$((10#$n))"
    return
  fi
  n=${1#"$prefix"}
  n=$(printf '%s' "$n" | tr -dc '0-9')
  [ -n "$n" ] || {
    echo ""
    return
  }
  printf 'LT-%06d\n' "$((10#$n))"
}

say ".tixforge/.gitignore を作る"
run ensure_workspace "$top"

# --- config -----------------------------------------------------------------
if [ -f "$old_conf" ]; then
  say "$old_conf -> .tixforge/config.yml（default_branch -> base_branch、prefix・pad を削除）"
  if [ -n "$apply" ]; then
    if [ -f .tixforge/config.yml ]; then
      echo "  .tixforge/config.yml が既にある：上書きしない" >&2
    else
      sed -e 's/^\([[:space:]]*\)default_branch:/\1base_branch:/' -e '/^[[:space:]]*prefix:/d' -e '/^[[:space:]]*pad:/d' \
        -e 's/^# \/flow settings/# tixforge settings/' "$old_conf" > .tixforge/config.yml
      if tracked "$old_conf"; then git rm -q "$old_conf"; else rm -f "$old_conf"; fi
    fi
  fi
fi

# --- tickets and runs --------------------------------------------------------
ids=$({
  ls docs/tickets 2> /dev/null | sed -n 's/\.md$//p'
  for d in docs/flow/*; do
    [ -e "$d" ] || continue
    printf '%s\n' "${d##*/}"
  done
} | sort -u)
for old in $ids; do
  t="docs/tickets/$old.md"
  [ -f "$t" ] || t=""
  new=$(new_id "$old" "$t")
  [ -n "$new" ] || {
    echo "  ${old}：番号が読めないので移さない" >&2
    continue
  }
  if [ -n "$t" ]; then
    say "$t -> .tixforge/$new/ticket.md"
    if [ -n "$apply" ]; then
      mkdir -p ".tixforge/$new"
      {
        title=$(sed -n '1{s/^# *//; s/^[^:]*: *//; p;}' "$t")
        printf '# %s: %s\n' "$new" "$title"
        # Status / Reason lines stay for local tickets only (a GT ticket's
        # issue says whether it is canceled).
        case $new in LT-*) awk '/^## / { exit } /^(Status|Reason):/' "$t" ;; esac
        printf '\n'
        awk '/^## / { on = 1 } on' "$t"
      } > ".tixforge/$new/ticket.md"
      if tracked "$t"; then git rm -q "$t"; else rm -f "$t"; fi
    fi
  fi
  if [ -f "docs/flow/$old/main.md" ]; then
    say "docs/flow/$old/main.md -> .tixforge/$new/state.md"
    if [ -n "$apply" ]; then
      mkdir -p ".tixforge/$new"
      sed -e "1s/.*/# Run: $new/" -e '/^| Ticket  |/d' -e '/^| Issue   |/d' "docs/flow/$old/main.md" > ".tixforge/$new/state.md"
      rm -rf "docs/flow/$old"
    fi
  fi
done
if [ -e docs/flow/.active ]; then
  say "docs/flow/.active を削除"
  run rm -f docs/flow/.active
fi
if [ -n "$apply" ]; then
  for d in docs/flow docs/tickets; do
    [ -d "$d" ] || continue
    find "$d" -type d -empty -delete 2> /dev/null
    [ -d "$d" ] && echo "  $d に移していないファイルが残っている：中身を確かめて、要らなければ消す" >&2
  done
fi

# --- workflows ---------------------------------------------------------------
for n in issue-sync issue-guard pr-link; do
  old=".github/workflows/flow-$n.yml"
  [ -f "$old" ] || continue
  say "$old -> .github/workflows/tixforge-$n.yml（plugin の最新の雛形）"
  if [ -n "$apply" ]; then
    cp "$here/../templates/github/tixforge-$n.yml" ".github/workflows/tixforge-$n.yml"
    if tracked "$old"; then git rm -q "$old"; else rm -f "$old"; fi
  fi
done
if [ -f .github/workflows/flow-ci.yml ]; then
  say ".github/workflows/flow-ci.yml -> tixforge-ci.yml（中身はプロジェクトに合わせたものなので、名前だけ変える）"
  if [ -n "$apply" ]; then
    sed -e 's/^name: flow-ci/name: tixforge-ci/' -e 's/flow-command template: flow-ci/tixforge template: tixforge-ci/' \
      .github/workflows/flow-ci.yml > .github/workflows/tixforge-ci.yml
    if tracked .github/workflows/flow-ci.yml; then git rm -q .github/workflows/flow-ci.yml; else rm -f .github/workflows/flow-ci.yml; fi
  fi
fi
if [ -d .github/flow ]; then
  say ".github/flow/ -> .github/tixforge/（ticket-hash.sh と messages.yml を plugin の最新に）"
  if [ -n "$apply" ]; then
    mkdir -p .github/tixforge
    cp "$here/ticket-hash.sh" "$here/messages.yml" .github/tixforge/
    git rm -rq .github/flow 2> /dev/null || rm -rf .github/flow
  fi
fi

# --- GitHub ------------------------------------------------------------------
if [ -n "$github" ]; then
  if ! bash "$here/github-preflight.sh" > /dev/null; then
    echo "GitHub の操作は行わない：$(bash "$here/github-preflight.sh")" >&2
  else
    have=$(gh label list --limit 200 --json name --jq '.[].name')
    for l in todo in-progress in-review out-of-sync; do
      printf '%s\n' "$have" | grep -qx "flow:$l" || continue
      if ! printf '%s\n' "$have" | grep -qx "tixforge:$l"; then
        say "ラベル flow:${l} -> tixforge:${l}（付いている issue ごと名前を変える）"
        run gh label edit "flow:$l" --name "tixforge:$l" > /dev/null
        continue
      fi
      # Both exist (tixforge was set up before): move the issues, then drop
      # the old label.
      for n in $(gh issue list --state all --limit 1000 --label "flow:$l" --json number --jq '.[].number'); do
        say "#${n} の flow:${l} を tixforge:${l} に付け替える"
        run gh issue edit "$n" --remove-label "flow:$l" --add-label "tixforge:$l" > /dev/null
      done
      say "ラベル flow:${l} を削除する（issue は付け替え済み）"
      run gh label delete "flow:$l" --yes > /dev/null
    done
    say "足りない tixforge のラベルを作る"
    run bash "$here/issue-label.sh" setup
    nums=$(gh issue list --state all --limit 1000 --search 'label:tixforge:todo,tixforge:in-progress,tixforge:in-review,tixforge:out-of-sync,flow:todo,flow:in-progress,flow:in-review' --json number --jq '.[].number' 2> /dev/null | sort -un)
    tmpb=$(mktemp) || exit 1
    for n in $nums; do
      info=$(gh issue view "$n" --json state,stateReason --jq '.state + " " + (.stateReason // "")')
      gh issue view "$n" --json body --jq .body > "$tmpb"
      if grep -q '<!-- flow:' "$tmpb"; then
        say "#$n の本文の目印を tixforge: に書き換える（ハッシュは本文とタイトルから計算するので変わらない）"
        if [ -n "$apply" ]; then
          sed -e 's/<!-- flow:hash:/<!-- tixforge:hash:/' -e 's/<!-- flow:ticket:start -->/<!-- tixforge:ticket:start -->/' \
            -e 's/<!-- flow:ticket:end -->/<!-- tixforge:ticket:end -->/' \
            -e 's/`\/flow` がチケットと同期/tixforge がチケットと同期/' -e 's/by `\/flow`/by tixforge/' \
            -e 's/`\/flow edit`/`\/tixforge:ticket edit`/g' "$tmpb" > "$tmpb.new"
          gh issue edit "$n" --body-file "$tmpb.new" > /dev/null
        fi
      fi
      case $info in
        "CLOSED NOT_PLANNED")
          if gh issue view "$n" --json comments --jq '.comments[].body' | grep -q '^Canceled by /flow: '; then
            say "#${n}（キャンセル済み）に tixforge:canceled を付ける"
            run bash "$here/issue-label.sh" "$n" canceled
          fi
          ;;
        "CLOSED COMPLETED")
          say "#${n}（完了）に tixforge:done を付ける"
          run bash "$here/issue-label.sh" "$n" done
          ;;
      esac
    done
    rm -f "$tmpb" "$tmpb.new"
  fi
fi

echo
if [ -n "$apply" ]; then
  echo "移行した。git status で変更を確かめ、まとめて commit する（.tixforge/ の中は config.yml と .gitignore だけが git に載る）。"
  echo "プロジェクトの .gitignore にある docs/flow/・docs/tickets/ の行は不要になったので、消してよい。"
else
  echo "これは試し実行。実行するには --apply を付ける（GitHub のラベルと issue も移すなら --github も）。"
fi
